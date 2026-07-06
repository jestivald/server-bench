<h1 align="center">🚀 Server Bench</h1>

<p align="center">
  <b>Вся диагностика и бенчмарки сервера одной командой</b><br>
  <sub>Одна команда. Красивый вывод. Всё, что нужно, чтобы проверить VPS.</sub>
</p>

<p align="center">
  <a href="README.md">🇬🇧 English version</a>
</p>

<p align="center">
  <img src="https://img.shields.io/github/v/tag/jestivald/server-bench?style=for-the-badge&label=version&color=blueviolet" alt="Version">
  <img src="https://img.shields.io/github/actions/workflow/status/jestivald/server-bench/lint.yml?style=for-the-badge&label=lint" alt="Lint">
  <img src="https://img.shields.io/github/actions/workflow/status/jestivald/server-bench/smoke.yml?style=for-the-badge&label=smoke%20test" alt="Smoke">
  <img src="https://img.shields.io/badge/platform-linux-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/license-MIT-blue?style=for-the-badge" alt="License">
</p>

<p align="center">
  <img src="assets/demo.svg" alt="демо server-bench" width="680">
</p>

## ⚡ Быстрый старт

Запуск на любом сервере, ничего устанавливать не нужно:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh)
```

Быстрая проверка (система + сеть + безопасность + docker, ~1 мин):

```bash
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick
```

Сохранить результаты в файл:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick 2>&1 | tee bench-results.txt
```

> Зависимости (sysbench, fio, dnsutils) ставятся автоматически — но только те,
> что реально нужны выбранным модулям. Флаг `--no-install` запрещает любую
> установку пакетов.

**Режим отчёта (v2.1):** если модулей больше одного и запуск идёт в терминале,
тесты выполняются тихо за прогресс-чеклистом (`[████░░░░] 44% ► speed-ru 2m 14s`),
а по завершении печатается **структурированный итог** — больше никаких простыней
текста, улетающих мимо глаз. Полный текстовый отчёт заодно автоматически
сохраняется в `./server-bench-<время>.log`. Хочешь старый живой вывод — добавь
`--live`.

## 🧪 Что проверяется

| Модуль | Флаг | Что делает | Время |
|:---|:---|:---|:---|
| 📋 Система | `--info` | ОС, CPU (модель/steal%/AES-NI), виртуализация, RAM, диски, IP, гео, rDNS, sysbench CPU (1 + N потоков) | ~30с |
| 💾 Диск | `--disk` | fio: последовательные 1M чтение/запись + случайные 4K IOPS, direct I/O на реальном (не tmpfs) пути; фолбэк dd | ~1мин |
| 🌐 Сеть | `--network` | TCP-стек (BBR? qdisc? MTU), исходящий 25-й порт, пинг с потерями, скорость DNS | ~30с |
| 🔒 Безопасность | `--security` | Эффективный конфиг sshd (`sshd -T` с drop-in'ами), фаервол (ufw/nft/iptables), fail2ban, обновления | ~10с |
| 🐳 Docker | `--docker` | Статус контейнеров, количество, занятое место | ~5с |
| 🔍 Проверка IP | `--ip` | Репутация IP ([IP.Check.Place](https://ip.check.place)) + определение региона ([ipregion](https://github.com/vernette/ipregion)) | ~3мин |
| 🇷🇺 Скорость РФ | `--speed-ru` | Замер скорости до российских провайдеров (bench.gig.ovh / bench.tlab.pw) | ~5мин |
| 🌍 Скорость мир | `--speed-int` | Замер скорости до зарубежных провайдеров (bench.sh / speed.tlab.pw) | ~5мин |
| 📸 Instagram | `--instagram` | Проверка блокировки аудио в Instagram (bench.openode.xyz) | ~30с |
| 🛡️ DPI | `--dpi` | Проверка DPI-блокировок для российских серверов ([censorcheck](https://github.com/vernette/censorcheck)) | ~1мин |
| 📊 YABS | `--yabs` | Классический [yabs.sh](https://github.com/masonr/yet-another-bench-script): fio + iperf3 + Geekbench 6 | ~20мин |

`--all` (по умолчанию) запускает всё, кроме `--instagram`, `--dpi` и `--yabs` — они включаются отдельно.

## 🎯 Использование

```bash
# полный набор тестов
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --all

# быстрая проверка здоровья сервера
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick

# выбери нужное (флаги комбинируются)
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --info --disk --network

# машиночитаемо: JSON в stdout, человеческий отчёт в stderr
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --json --quick 2>/dev/null

# результат можно постить публично — IP замаскированы (a.b.x.x)
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick --hide-ip
```

### Опции

| Флаг | Эффект |
|:---|:---|
| `--report` | Прогресс-чеклист + структурированный итог + автосохранение в файл (по умолчанию при нескольких модулях в терминале) |
| `--live` | Живой вывод тестов по мере выполнения (по умолчанию для одного модуля) |
| `--json` | JSON-объект в stdout (только локальные модули), отчёт — в stderr |
| `--hide-ip` | Маскирует публичные IP — результат безопасно постить в чаты/форумы |
| `--no-install` | Никогда не ставить пакеты; тесты деградируют без падения |
| `--no-color` | Без цветов (переменная окружения `NO_COLOR` тоже работает) |
| `--version` / `--help` | Ну ты понял |

### Пример JSON-вывода

```json
{"version":"2.0.0","os":"Debian GNU/Linux 12 (bookworm)","virt":"kvm",
 "cpu_cores":4,"cpu_eps_1t":2847.31,"cpu_steal_pct":0.3,
 "disk_seq_write_mbs":412.7,"disk_rand_read_iops":48210,
 "tcp_cc":"bbr","qdisc":"fq","ping_yandex_avg_ms":38.2,
 "ssh_password_auth":"no","fail2ban":"yes","fails":0,"warns":1}
```

## 📋 Требования

- Linux (Debian, Ubuntu, CentOS, Fedora, AlmaLinux, Rocky)
- bash 4+, curl
- root **или** sudo желательно (автоустановка + привилегированные проверки);
  работает и без прав — часть проверок пропускается

Каждый пуш прогоняется smoke-тестом на реальном Ubuntu-раннере: полный
локальный набор (`--info --disk --network --security --docker`) обязан
отработать от начала до конца.

## 🔗 Под капотом

Тяжёлую работу во внешних модулях делают известные комьюнити-скрипты,
выполняются на лету (с таймаутами):

| Проверка | Апстрим |
|:---|:---|
| Репутация IP | [IP.Check.Place](https://ip.check.place) |
| Регион IP | [vernette/ipregion](https://github.com/vernette/ipregion) |
| DPI-цензура | [vernette/censorcheck](https://github.com/vernette/censorcheck) |
| Скорость РФ | bench.gig.ovh, bench.tlab.pw |
| Скорость мир | [bench.sh](https://bench.sh) (teddysun), speed.tlab.pw |
| Instagram аудио | bench.openode.xyz |
| YABS | [masonr/yet-another-bench-script](https://github.com/masonr/yet-another-bench-script) |

Локальные модули (info/disk/network/security/docker) самодостаточны и
используют `sysbench`, `fio`, `dd`, `ping`, `dig` напрямую.

> ⚠️ Внешние модули скачивают и выполняют сторонние скрипты — такова природа
> этого инструмента. Если модель угроз не позволяет — проверь апстримы выше
> или используй только локальные модули.

## 📝 Изменения

**v2.1** — 2026-07-06
- **Режим отчёта**: при нескольких модулях вместо бегущего текста — прогресс-чеклист с процентовкой, а в конце структурированный итог (локальные модули целиком, спидтесты сжаты до таблиц результатов, IP-чек — до ключевых строк)
- Полный текстовый отчёт **автосохраняется** в `./server-bench-<время>.log` (без ANSI-кодов)
- `--live` — старый живой вывод, `--report` — форсировать режим отчёта для одного модуля

**v2.0** — 2026-07-06
- Больше не умирает на середине: убран хрупкий `set -e`, каждая проверка деградирует без падения; в итогах — счётчики fail/warn и время каждого модуля
- Работает под голым root без установленного `sudo` (типичный VPS); никогда не спрашивает пароль в неинтерактивном запуске
- Честный диск-бенч: fio с direct I/O на реальной (не tmpfs) файловой системе, проверка свободного места, dd как фолбэк
- Зависимости ставятся лениво — только под выбранные модули; `--help` больше не трогает apt 🙃
- Новое: `--yabs`, `--json`, `--hide-ip`, `--no-install`, `--no-color`, `--version`
- Новые проверки: CPU steal%, тип виртуализации, AES-NI, многопоточный sysbench, BBR/qdisc/MTU, исходящий 25-й порт, потери пакетов, rDNS, эффективный конфиг sshd (включая drop-in'ы), nftables
- Внешние скрипты — с таймаутами, stderr больше не глушится; правильные имена пакетов для yum/dnf; CI: shellcheck + smoke-тест на реальном раннере

<details>
<summary><b>v1.0</b></summary>

- Первый релиз: инфо о системе, dd-тест диска, ping/DNS, аудит SSH/фаервола, статус docker, обёртки для IP.Check.Place / ipregion / bench.sh / bench.gig.ovh / censorcheck / Instagram-чекера
</details>

## 📄 Лицензия

MIT
