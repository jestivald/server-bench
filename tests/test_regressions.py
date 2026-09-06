"""Offline regression tests: no package installs, external scripts or server load."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "server-bench.sh"
BASH = shutil.which("bash")


class BenchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="server-bench-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "work").mkdir()
        self.trace = self.root / "trace"
        self.trace.touch()

    def run_bash(self, body, *, env=None, check=True):
        case = self.root / "case.sh"
        case.write_text('source "$1"\nWORK_DIR="$TEST_DIR/work"\nexec 3>&1\n' + body)
        result = subprocess.run(
            [BASH, str(case), str(SCRIPT)], cwd=self.root, text=True,
            capture_output=True, timeout=20,
            env={**os.environ, "TEST_DIR": str(self.root), "TMPDIR": str(self.root),
                 "TEST_TRACE": str(self.trace), "LC_ALL": "C", **(env or {})},
        )
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def metrics(self, body, **kwargs):
        result = self.run_bash('JSON_MODE=1\n{\n' + body + '\n} >&2\nemit_json\n', **kwargs)
        return json.loads(result.stdout)

    def terse(self, error=0):
        fields = ["0"] * 121
        for index, value in {1: "3", 2: "fio-3.33", 3: "bench", 5: str(error),
                             7: "102400", 8: "25600", 48: "204800", 49: "51200"}.items():
            fields[index - 1] = value
        fixture = self.root / "fio.txt"
        fixture.write_text(";".join(fields) + "\ntrailing diagnostic text\n")
        return fixture

    def test_json_preserves_control_characters_and_unicode(self):
        value = 'host "test" \\ путь ' + "".join(chr(i) for i in range(1, 32))
        result = self.metrics('record text "$TEST_VALUE"', env={"TEST_VALUE": value})
        self.assertEqual(result["text"], value)

    def test_json_rejects_invalid_numbers(self):
        result = self.metrics('''
record leading_zero 08 num
record missing "" num
record invalid NaN num
record exponent 1.25e3 num
''')
        self.assertEqual(result, {"leading_zero": None, "missing": None,
                                  "invalid": None, "exponent": 1250})

    def test_options_without_modules_use_default_suite(self):
        result = self.run_bash('''
uname() { echo Linux; }
init_privileges() { :; }
ensure_deps() { :; }
command_exists() { return 0; }
show_banner() { :; }
show_summary() { :; }
run_module() { echo "$2"; }
main --no-color
''')
        self.assertEqual(result.stdout.splitlines(), ["info", "disk", "network", "security",
                         "docker", "ip-check", "ip-region", "speed-ru", "speed-int"])

    def test_selection_is_additive_and_deduplicated(self):
        result = self.run_bash('''
select_preset quick
select_modules info geoblock info
selected_count
''')
        self.assertEqual(result.stdout, "5")

    def test_menu_accepts_ranges_and_rejects_invalid_input_atomically(self):
        result = self.run_bash('''
parse_menu_selection '1,3-5,08' || exit 1
echo "${SELECTED_MODULES[*]}"
for input in '0' '99' '5-2' '1 2 broken' '1-99' '99999999999'; do
    if parse_menu_selection "$input"; then exit 1; fi
done
echo "${SELECTED_MODULES[*]}"
''')
        expected = "1 0 1 1 1 0 0 1 0 0 0 0 0"
        self.assertEqual(result.stdout.splitlines(), [expected, expected])

    def test_menu_does_not_start_without_a_terminal(self):
        result = self.run_bash('main --menu', check=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("interactive terminal", result.stderr)
        self.assertEqual(list(self.root.glob("server-bench.*")), [])

    def test_help_list_version_do_not_probe_or_install(self):
        for flag in ("--help", "--list", "--version"):
            with self.subTest(flag=flag):
                result = self.run_bash('''
init_privileges() { echo unexpected >&2; return 1; }
ensure_deps() { echo unexpected >&2; return 1; }
uname() { echo unexpected >&2; return 1; }
main "$TEST_FLAG"
''', env={"TEST_FLAG": flag})
                self.assertNotIn("unexpected", result.stderr)
                self.assertTrue(result.stdout.strip())

    def test_mktemp_failure_stops_before_modules(self):
        result = self.run_bash('''
uname() { echo Linux; }
init_privileges() { :; }
mktemp() { return 1; }
run_module() { echo unexpected; }
main --security --no-install
''', check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("temporary work directory", result.stdout)
        self.assertNotIn("unexpected", result.stdout)

    def test_dependency_install_is_batched_and_apt_updated_once(self):
        self.run_bash('''
can_priv() { return 0; }
detect_pm() { PM=apt-get; }
command_exists() { return 1; }
run_priv() { printf '%s\\n' "$*" >> "$TEST_TRACE"; }
ensure_deps sysbench fio dig dig
ensure_deps ping
''')
        calls = self.trace.read_text().splitlines()
        self.assertEqual(sum("apt-get update" in line for line in calls), 1)
        installs = [line for line in calls if "apt-get install" in line]
        self.assertEqual(len(installs), 2)
        self.assertIn("sysbench fio dnsutils", installs[0])
        self.assertIn("iputils-ping", installs[1])

    def test_no_install_does_not_invoke_package_manager(self):
        self.run_bash('''
NO_INSTALL=1
command_exists() { return 1; }
run_priv() { echo unexpected >> "$TEST_TRACE"; }
ensure_deps fio sysbench
''')
        self.assertEqual(self.trace.read_text(), "")

    def security_metrics(self, status, rc=0):
        return self.metrics('''
command_exists() { [[ "$1" == ufw ]]; }
run_priv() {
    case "$1" in
        sshd) return 1 ;;
        ufw) printf '%s\\n' "$TEST_UFW"; return "$TEST_UFW_RC" ;;
    esac
}
test_security
''', env={"TEST_UFW": status, "TEST_UFW_RC": str(rc)})

    def test_inactive_ufw_is_not_reported_active(self):
        self.assertEqual(self.security_metrics("Status: inactive")["firewall"], "ufw-inactive")

    def test_active_ufw_is_reported_active(self):
        self.assertEqual(self.security_metrics("Status: active")["firewall"], "ufw-active")

    def test_ufw_permission_failure_is_unknown(self):
        self.assertEqual(self.security_metrics("", 1)["firewall"], "unknown")
        self.assertEqual(self.security_metrics("Status: active", 1)["firewall"], "unknown")

    def test_failed_apt_query_does_not_claim_zero_updates(self):
        result = self.metrics('''
command_exists() { [[ "$1" == apt ]]; }
run_priv() { return 1; }
timeout() { return 1; }
test_security
''')
        self.assertIsNone(result["pending_updates"])

    def test_fio_error_record_is_not_a_valid_measurement(self):
        self.terse(error=22)
        result = self.run_bash('''
DISK_FILE="$TEST_DIR/disk"
FIO_ENG=psync
timeout() { shift 3; "$@"; }
fio() { echo "$*" >> "$TEST_TRACE"; cat "$TEST_DIR/fio.txt"; }
if fio_job test "$WORK_DIR/fio.log" --rw=write; then exit 1; fi
''')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(self.trace.read_text().splitlines()), 1)
        self.assertNotIn("--direct=0", self.trace.read_text())

    def test_fio_nonzero_exit_rejects_success_looking_output(self):
        self.terse()
        self.run_bash('''
DISK_FILE="$TEST_DIR/disk"
FIO_ENG=psync
timeout() { shift 3; "$@"; }
fio() { cat "$TEST_DIR/fio.txt"; return 1; }
if fio_job test "$WORK_DIR/fio.log" --rw=write; then exit 1; fi
''')

    def test_disk_values_and_random_test_duration(self):
        self.terse()
        result = self.metrics('''
pick_disk_dir() { printf '%s\\text4\\t2000000\\n' "$TEST_DIR"; }
command_exists() { [[ "$1" == fio ]]; }
timeout() { shift 3; "$@"; }
fio() {
    if [[ "$1" == --enghelp ]]; then echo libaio; return; fi
    echo "$*" >> "$TEST_TRACE"
    cat "$TEST_DIR/fio.txt"
}
test_disk
''')
        self.assertEqual(result["disk_seq_read_mbs"], 100)
        self.assertEqual(result["disk_seq_write_mbs"], 200)
        self.assertEqual(result["disk_rand_read_iops"], 25600)
        self.assertEqual(result["disk_rand_write_iops"], 51200)
        random_jobs = [line for line in self.trace.read_text().splitlines() if "--rw=rand" in line]
        self.assertEqual(len(random_jobs), 2)
        self.assertTrue(all("--time_based --runtime=10" in line for line in random_jobs))
        self.assertEqual(list(self.root.glob(".server-bench-fio.*")), [])

    def test_disk_search_continues_past_full_filesystem(self):
        result = self.run_bash('''
df() {
    case "$1" in
        --output=fstype) echo ext4 ;;
        --output=avail)
            if [[ "$2" == "$PWD" ]]; then echo 100; else echo 1000000; fi ;;
    esac
}
pick_disk_dir
''')
        self.assertNotEqual(result.stdout.split("\t")[0], str(self.root))

    def test_external_scripts_are_not_fetched_in_restricted_modes(self):
        for flag in ("NO_INSTALL", "HIDE_IP"):
            with self.subTest(flag=flag):
                result = self.run_bash(f'''
{flag}=1
curl() {{ echo unexpected >> "$TEST_TRACE"; }}
run_external example 10 https://example.invalid/test.sh
echo "skips=$SKIPS"
''')
                self.assertIn("skips=1", result.stdout)
        self.assertEqual(self.trace.read_text(), "")

    def test_html_and_invalid_scripts_are_rejected_before_execution(self):
        for value in ("   <!doctype html>\n<html>oops</html>", "if then broken"):
            with self.subTest(value=value):
                result = self.run_bash('''
curl() { printf '%s' "$TEST_BODY" > "${@: -1}"; }
timeout() { echo unexpected >> "$TEST_TRACE"; }
if run_external example 10 https://example.invalid/test.sh; then exit 1; fi
''', env={"TEST_BODY": value})
                self.assertIn("valid Bash script", result.stdout)
        self.assertEqual(self.trace.read_text(), "")

    def test_geoblock_passes_explicit_mode(self):
        result = self.run_bash('''
run_external() { printf '%s\\n' "$*"; }
test_geoblock
''')
        self.assertIn("--mode geoblock", result.stdout)

    def test_module_status_reflects_failures_warnings_and_skips(self):
        result = self.metrics('''
REPORT_MODE=1
TOTAL_MODULES=3
failed_test() { status_fail broken; }
warning_test() { status_warn limited; }
skipped_test() { status_skip unavailable; }
run_module failed_test disk
run_module warning_test security
run_module skipped_test geoblock
''')
        self.assertEqual(result["module_disk_status"], "failed")
        self.assertEqual(result["module_security_status"], "warning")
        self.assertEqual(result["module_geoblock_status"], "skipped")

    def test_unhandled_module_exit_is_a_failure(self):
        result = self.metrics('''
broken_test() { return 7; }
run_module broken_test fixture
''')
        self.assertEqual(result["module_fixture_status"], "failed")

    def test_docker_preserves_empty_ports_and_counts_one_snapshot(self):
        result = self.metrics('''
command_exists() { [[ "$1" == docker ]]; }
timeout() { shift 3; "$@"; }
docker() {
    echo "$*" >> "$TEST_TRACE"
    case "$1" in
        info) return 0 ;;
        ps) printf 'api|Up 2 hours||example/api:v1|running\\nworker|Exited (0)||example/worker:v2|exited\\n' ;;
        system) echo 'Images 2' ;;
    esac
}
test_docker
''')
        self.assertEqual(result["docker_total"], 2)
        self.assertEqual(result["docker_running"], 1)
        self.assertEqual(sum(line.startswith("ps ") for line in self.trace.read_text().splitlines()), 1)

    def test_failed_docker_list_does_not_claim_zero_containers(self):
        result = self.metrics('''
command_exists() { [[ "$1" == docker ]]; }
timeout() { shift 3; "$@"; }
docker() { [[ "$1" == info ]]; }
test_docker
''')
        self.assertNotIn("docker_total", result)

    def test_saved_reports_are_private_and_do_not_overwrite(self):
        result = self.run_bash('''
DONE_TITLES=(security)
echo 'report contents' > "$(mod_log security)"
save_report
echo "$REPORT_FILE"
save_report
echo "$REPORT_FILE"
''')
        files = [Path(line) for line in result.stdout.splitlines() if line.startswith("/")]
        self.assertEqual(len(files), 2, result.stdout)
        self.assertNotEqual(files[0], files[1])
        for file in files:
            self.assertEqual(file.stat().st_mode & 0o777, 0o600)
            self.assertIn("report contents", file.read_text())
            self.assertIn("0 failed", file.read_text())

    def test_dns_failure_with_query_time_is_not_success(self):
        result = self.run_bash('''
command_exists() { [[ "$1" == dig ]]; }
timeout() { printf ';; Query time: 5 msec.\\n'; }
dns_probe example.invalid
''')
        self.assertEqual(result.stdout, "|5\n")

    def test_ping_and_dns_probes_run_concurrently(self):
        result = self.metrics('''
command_exists() { [[ "$1" == ping || "$1" == dig ]]; }
sysctl() { echo bbr; }
ip() { return 1; }
timeout() {
    [[ "$1" != -k ]] || shift 2
    shift
    case "$1" in ping|dig) "$@" ;; *) return 1 ;; esac
}
barrier() {
    echo started >> "$TEST_DIR/$1"
    local i
    for ((i=0; i<100; i++)); do
        [[ $(wc -l < "$TEST_DIR/$1") -ge $2 ]] && return 0
        sleep 0.01
    done
    return 1
}
ping() {
    barrier ping_started 4 || return 1
    printf '3 packets transmitted, 3 received, 0%% packet loss\\n'
    printf 'rtt min/avg/max/mdev = 10.0/14.3/20.0/1.0 ms\\n'
}
dig() {
    barrier dns_started 5 || return 1
    printf 'example.com. 60 IN A 192.0.2.1\\n;; Query time: 5 msec.\\n'
}
test_network
''')
        for name in ("cloudflare", "google", "yandex", "opendns"):
            self.assertEqual(result[f"ping_{name}_avg_ms"], 14.3)
            self.assertEqual(result[f"ping_{name}_loss_pct"], 0)
        self.assertEqual(result["dns_google_com_ms"], 5)
        self.assertEqual(result["dns_cloudflare_com_ms"], 5)

    def test_ru_speed_measures_both_directions(self):
        result = self.metrics('''
command_exists() { return 0; }
timeout() { shift 3; "$@"; }
iperf3() {
    echo "$*" >> "$TEST_TRACE"
    if [[ " $* " == *" -R "* ]]; then echo 50000000; else echo 100000000; fi
}
jq() { cat "${@: -1}"; }
test_speed_ru
''')
        self.assertEqual(result["speed_ru_completed"], 5)
        self.assertEqual(result["speed_ru_moscow_upload_mbps"], 100)
        self.assertEqual(result["speed_ru_moscow_download_mbps"], 50)
        calls = self.trace.read_text().splitlines()
        self.assertEqual(len(calls), 10)
        self.assertEqual(sum(" -R" in line for line in calls), 5)

    def test_ru_speed_retries_busy_ports(self):
        result = self.metrics('''
command_exists() { return 0; }
timeout() { shift 3; "$@"; }
iperf3() {
    echo "$*" >> "$TEST_TRACE"
    [[ " $* " != *" -p 5201 "* ]] || return 1
    echo 100000000
}
jq() { cat "${@: -1}"; }
test_speed_ru
''')
        self.assertEqual(result["speed_ru_completed"], 5)
        self.assertEqual(result["speed_ru_moscow_port"], 5202)
        self.assertEqual(len(self.trace.read_text().splitlines()), 15)


if __name__ == "__main__":
    unittest.main(verbosity=2)
