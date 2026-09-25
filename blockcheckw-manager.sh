cat > /root/blockcheckw-manager.sh <<'EOF'
#!/bin/sh
# BlockCheckW Manager v0.4.2

# Цвета
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    RED='\033[0;31m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    CYAN=''
    RED=''
    BOLD=''
    NC=''
fi

CFG="/root/.bcw.conf"
SELF="/root/blockcheckw-manager.sh"
LINK="/usr/bin/bcw"

# ─────────────────────────────────────────────────────────────────────────────
# ЗАФИКСИРОВАННАЯ ВЕРСИЯ blockcheckw
#
# Менеджер работает только с проверенной версией движка. В более новых версиях
# автор меняет поведение так, что подбор перестаёт работать, поэтому вместо
# "releases/latest" версия захардкожена.
#
# Почему v0.8.5:
#   В v0.9.5 появился коммит "снос чужих таблиц и рулсетов" (FIXES #66),
#   добавивший модуль firewall/nft.rs. Движок начинает удалять nft-таблицы и
#   ruleset'ы, которые ему не принадлежат: scan может находить стратегии, но
#   check не подтверждает ни одной.
#
#   Дополнительно: по v0.11.1 включительно движок ищет nfqws2 автоподбором по
#   /opt/zapret2/binaries/<arch>/nfqws2 (этот симлинк создаёт менеджер), а с
#   v0.11.2 путь жёстко зашит в /opt/zapret2/nfq2/nfqws2.
#
# Менять версию не рекомендуется. Если меняете — проверьте на роутере, что
# `blockcheckw check` даёт рабочие стратегии, а не только что scan что-то нашёл.
# ─────────────────────────────────────────────────────────────────────────────
BCW_VERSION="v0.8.5"
BCW_REPO="rcd27/blockcheckw"

# Глобальная переменная для состояния zapret
ZAPRET_WAS_RUNNING=0

pause(){ printf "\n${CYAN}Нажмите Enter...${NC}"; read x; }

save_cfg() {
cat > "$CFG" <<CFGEOF
WORKERS=$WORKERS
PROTO=$PROTO
DOMAINS=$DOMAINS
TIMEOUT=$TIMEOUT
DNS_MODE=$DNS_MODE
CFGEOF
}

init_cfg() {
[ -f "$CFG" ] || cat > "$CFG" <<CFGEOF
WORKERS=128
PROTO=tls12
DOMAINS=rutracker.org
TIMEOUT=600
DNS_MODE=auto
CFGEOF

. "$CFG"

[ -z "$WORKERS" ] && WORKERS=128
[ -z "$PROTO" ] && PROTO=tls12
[ -z "$DOMAINS" ] && DOMAINS=rutracker.org
[ -z "$TIMEOUT" ] && TIMEOUT=600
[ -z "$DNS_MODE" ] && DNS_MODE=auto

save_cfg
}

status_line() {
printf "${CYAN}${BOLD}Домены:${NC} ${GREEN}$DOMAINS${NC} | ${CYAN}${BOLD}Потоки:${NC} ${YELLOW}$WORKERS${NC} | ${CYAN}${BOLD}Протокол:${NC} ${YELLOW}$PROTO${NC} | ${CYAN}${BOLD}Таймаут:${NC} ${YELLOW}$TIMEOUT${NC}\n"
}

install_bcw() {
clear
printf "${CYAN}${BOLD}=========================================${NC}\n"
printf "${CYAN}${BOLD}  Установка / обновление blockcheckw${NC}\n"
printf "${CYAN}${BOLD}=========================================${NC}\n\n"

printf "${CYAN}Версия (зафиксирована):${NC} ${GREEN}${BOLD}${BCW_VERSION}${NC}\n\n"

cd /tmp || return

printf "${YELLOW}→ Формирование ссылки на версию ${BCW_VERSION}...${NC}\n"
URL="https://github.com/${BCW_REPO}/releases/download/${BCW_VERSION}/blockcheckw-linux-arm64.tar.gz"
printf "${GREEN}✓ Ссылка:${NC} ${URL##*/}\n\n"

printf "${YELLOW}→ Подготовка временной директории...${NC}\n"
rm -rf /tmp/bcwtmp
mkdir -p /tmp/bcwtmp
cd /tmp/bcwtmp || return
printf "${GREEN}✓ Готово${NC}\n\n"

printf "${YELLOW}→ Загрузка архива...${NC}\n"
if ! wget -O bcw.tar.gz "$URL"; then
    printf "\n${RED}${BOLD}Ошибка загрузки.${NC}\n"
    printf "${YELLOW}Проверьте интернет на роутере и что релиз ${BCW_VERSION} доступен.${NC}\n"
    pause
    return
fi
printf "${GREEN}✓ Загрузка завершена${NC}\n\n"

printf "${YELLOW}→ Распаковка...${NC}\n"
if ! tar -xzf bcw.tar.gz; then
    printf "${RED}${BOLD}Ошибка распаковки.${NC}\n"
    pause
    return
fi
printf "${GREEN}✓ Распаковано${NC}\n\n"

printf "${YELLOW}→ Поиск исполняемого файла...${NC}\n"
BIN="$(find . -type f -name blockcheckw | head -1)"
if [ -z "$BIN" ]; then
    printf "${RED}${BOLD}Файл blockcheckw не найден.${NC}\n"
    pause
    return
fi
printf "${GREEN}✓ Найден:${NC} $BIN\n\n"

printf "${YELLOW}→ Установка в /usr/bin/...${NC}\n"
cp "$BIN" /usr/bin/blockcheckw
chmod +x /usr/bin/blockcheckw
printf "${GREEN}✓ Установлено${NC}\n\n"

printf "${YELLOW}→ Настройка окружения...${NC}\n"
# Обязательно для этой версии: движок ищет nfqws2 в
# /opt/zapret2/binaries/<arch>/nfqws2, а в zapret2 он лежит в nfq2/.
mkdir -p /opt/zapret2/binaries/linux-arm64
if [ -f /opt/zapret2/nfq2/nfqws2 ]; then
    ln -sf /opt/zapret2/nfq2/nfqws2 /opt/zapret2/binaries/linux-arm64/nfqws2
    printf "${GREEN}✓ Симлинк nfqws2 создан${NC}\n"
else
    printf "${RED}${BOLD}ВНИМАНИЕ: /opt/zapret2/nfq2/nfqws2 не найден!${NC}\n"
    printf "${YELLOW}blockcheckw не сможет работать без nfqws2.${NC}\n"
    printf "${YELLOW}Установите/переустановите zapret2 и повторите.${NC}\n\n"
fi

ln -sf "$SELF" "$LINK"
printf "${GREEN}✓ Симлинк менеджера создан (bcw)${NC}\n\n"

printf "${GREEN}${BOLD}=========================================${NC}\n"
printf "${GREEN}${BOLD}  Установка завершена${NC}\n"
printf "${GREEN}${BOLD}=========================================${NC}\n\n"

printf "${YELLOW}→ Проверка работоспособности...${NC}\n"
VERSION="$(/usr/bin/blockcheckw --version 2>/dev/null </dev/null | head -1)"
case "$VERSION" in
    *"${BCW_VERSION}"*)
        printf "${GREEN}✓${NC} ${VERSION}\n"
        ;;
    "")
        printf "${RED}✗ Не удалось определить версию движка.${NC}\n"
        ;;
    *)
        printf "${YELLOW}⚠ Установлена другая версия:${NC} ${VERSION}\n"
        printf "${YELLOW}  Ожидалась ${BCW_VERSION} — менеджер может работать некорректно.${NC}\n"
        ;;
esac

if [ -x /opt/zapret2/binaries/linux-arm64/nfqws2 ]; then
    printf "${GREEN}✓${NC} nfqws2 доступен движку\n"
else
    printf "${RED}✗ nfqws2 недоступен — поиск не запустится.${NC}\n"
fi

printf "\n${CYAN}Команда запуска:${NC} ${BOLD}bcw${NC}\n"
pause
}

remove_all() {
clear
printf "${YELLOW}Удаление blockcheckw и настроек...${NC}\n"
rm -f /usr/bin/blockcheckw "$LINK" "$CFG"
printf "${GREEN}✓ Удалено${NC}\n"
pause
}

choose_proto() {
clear
echo "1. http"
echo "2. tls12"
echo "3. tls13"
echo "4. всё"
printf "Выбор: "
read A
case "$A" in
1) PROTO=http ;;
2) PROTO=tls12 ;;
3) PROTO=tls13 ;;
4) PROTO=http,tls12,tls13 ;;
*) ;;
esac
save_cfg
}

choose_dns() {
clear
echo "Выберите режим DNS (для запросов blockcheckw, не влияет на роутер):"
echo ""
echo "1. auto (автоопределение, DoH при подмене) - по умолчанию"
echo "2. system (системный DNS роутера)"
echo "3. doh (DNS over HTTPS, Cloudflare)"
echo ""
printf "Выбор: "
read A
case "$A" in
1) DNS_MODE=auto ;;
2) DNS_MODE=system ;;
3) DNS_MODE=doh ;;
*) ;;
esac
save_cfg
printf "\n${GREEN}✓ DNS режим установлен: ${YELLOW}%s${NC}\n" "$DNS_MODE"
pause
}

settings_menu() {
while true
do
clear
printf "${CYAN}${BOLD}==================================${NC}\n"
printf "${CYAN}${BOLD} Настройки${NC}\n"
printf "${CYAN}${BOLD}==================================${NC}\n"
echo "1. Потоки ($WORKERS)"
echo "2. Протокол ($PROTO)"
echo "3. Таймаут ($TIMEOUT)"
echo "4. Ввести / изменить домены"
echo "5. Показать домены"
echo "6. Очистить домены"
echo "7. DNS режим ($DNS_MODE)"
echo "0. Назад"
printf "${CYAN}${BOLD}==================================${NC}\n"
printf "Выбор: "
read S

case "$S" in
1) printf "Потоки: "; read WORKERS; [ -z "$WORKERS" ] && WORKERS=128; save_cfg ;;
2) choose_proto ;;
3) printf "Таймаут: "; read TIMEOUT; [ -z "$TIMEOUT" ] && TIMEOUT=600; save_cfg ;;
4) printf "Домены: "; IFS= read -r DOMAINS; [ -z "$DOMAINS" ] && DOMAINS=rutracker.org; save_cfg ;;
5) printf "${GREEN}%s${NC}\n" "$DOMAINS"; pause ;;
6) DOMAINS=rutracker.org; save_cfg; printf "${GREEN}Домены сброшены.${NC}\n"; pause ;;
7) choose_dns ;;
0) return ;;
esac
done
}

zapret_stop() {
    ZAPRET_WAS_RUNNING=0
    
    if [ -x /etc/init.d/zapret2 ]; then
        if /etc/init.d/zapret2 status 2>/dev/null | grep -q "running"; then
            ZAPRET_WAS_RUNNING=1
            printf "\n${YELLOW}Останавливаем zapret2...${NC}\n"
            /etc/init.d/zapret2 stop >/dev/null 2>&1
            sleep 2
            printf "${GREEN}zapret2 остановлен${NC}\n"
        else
            printf "\n${CYAN}zapret2 не запущен, пропускаем остановку.${NC}\n"
        fi
    fi
}

zapret_start() {
    if [ "$ZAPRET_WAS_RUNNING" = "1" ]; then
        if [ -x /etc/init.d/zapret2 ]; then
            printf "\n${YELLOW}Запускаем zapret2...${NC}\n"
            /etc/init.d/zapret2 start >/dev/null 2>&1
            sleep 2
            printf "${GREEN}zapret2 запущен${NC}\n"
        fi
    else
        printf "\n${CYAN}zapret2 не был остановлен скриптом, пропускаем запуск.${NC}\n"
    fi
}

cleanup_logs() {
clear
printf "${CYAN}${BOLD}=========================================${NC}\n"
printf "${CYAN}${BOLD}  Очистка логов и отчётов${NC}\n"
printf "${CYAN}${BOLD}=========================================${NC}\n\n"

QUICK_COUNT=$(ls -1 /root/*_quick.txt 2>/dev/null | wc -l)
WORKING_COUNT=$(ls -1 /root/*_working.txt 2>/dev/null | wc -l)
UNIVERSAL_JSON_COUNT=$(ls -1 /root/universal_*.json 2>/dev/null | wc -l)
UNIVERSAL_TXT_COUNT=$(ls -1 /root/universal_*.txt 2>/dev/null | wc -l)
UNIVERSAL_WORKING_COUNT=$(ls -1 /root/universal_working_*.txt 2>/dev/null | wc -l)
JSON_COUNT=$(ls -1 /root/*_report.json 2>/dev/null | wc -l)
SCAN_COUNT=$(ls -1 /root/*_scan.json 2>/dev/null | wc -l)
CHECK_COUNT=$(ls -1 /root/*_check.json 2>/dev/null | wc -l)
REPORT_COUNT=$(ls -1 /root/*_report_vanilla.txt 2>/dev/null | wc -l)

TOTAL=$((QUICK_COUNT + WORKING_COUNT + UNIVERSAL_JSON_COUNT + UNIVERSAL_TXT_COUNT + UNIVERSAL_WORKING_COUNT + JSON_COUNT + SCAN_COUNT + CHECK_COUNT + REPORT_COUNT))

if [ "$TOTAL" -eq 0 ]; then
    printf "${YELLOW}Нет файлов для удаления.${NC}\n"
    pause
    return
fi

printf "${YELLOW}Найдено файлов:${NC}\n"
printf "  Быстрые отчёты (*_quick.txt): ${CYAN}%s${NC}\n" "$QUICK_COUNT"
printf "  Рабочие стратегии (один домен) (*_working.txt): ${CYAN}%s${NC}\n" "$WORKING_COUNT"
printf "  Универсальные JSON (universal_*.json): ${CYAN}%s${NC}\n" "$UNIVERSAL_JSON_COUNT"
printf "  Универсальные TXT (universal_*.txt): ${CYAN}%s${NC}\n" "$UNIVERSAL_TXT_COUNT"
printf "  Универсальные проверенные (universal_working_*.txt): ${CYAN}%s${NC}\n" "$UNIVERSAL_WORKING_COUNT"
printf "  JSON отчёты (*_report.json): ${CYAN}%s${NC}\n" "$JSON_COUNT"
printf "  Scan JSON (*_scan.json): ${CYAN}%s${NC}\n" "$SCAN_COUNT"
printf "  Check JSON (*_check.json): ${CYAN}%s${NC}\n" "$CHECK_COUNT"
printf "  Vanilla отчёты (*_report_vanilla.txt): ${CYAN}%s${NC}\n" "$REPORT_COUNT"
printf "\n${RED}${BOLD}Всего: ${TOTAL} файлов${NC}\n\n"

printf "${RED}${BOLD}ВНИМАНИЕ! Все эти файлы будут удалены безвозвратно.${NC}\n"
printf "${YELLOW}Продолжить? (y/N): ${NC}"
read answer

case "$answer" in
    y|Y|yes|Yes|YES)
        rm -f /root/*_quick.txt 2>/dev/null
        rm -f /root/*_working.txt 2>/dev/null
        rm -f /root/universal_*.json 2>/dev/null
        rm -f /root/universal_*.txt 2>/dev/null
        rm -f /root/universal_working_*.txt 2>/dev/null
        rm -f /root/*_report.json 2>/dev/null
        rm -f /root/*_scan.json 2>/dev/null
        rm -f /root/*_check.json 2>/dev/null
        rm -f /root/*_report_vanilla.txt 2>/dev/null
        printf "\n${GREEN}✓ Удалено ${TOTAL} файлов.${NC}\n"
        ;;
    *)
        printf "\n${YELLOW}Очистка отменена.${NC}\n"
        ;;
esac
pause
}

run_quick_scan() {
clear
printf "${CYAN}${BOLD}=========================================${NC}\n"
printf "${CYAN}${BOLD}  Быстрый поиск (только сканирование)${NC}\n"
printf "${CYAN}${BOLD}=========================================${NC}\n"
status_line
echo ""

zapret_stop

printf "\n${CYAN}Нажмите Enter для запуска...${NC}"
read x
clear

printf "${YELLOW}${BOLD}Сканирование...${NC}\n"
echo ""

blockcheckw -w "$WORKERS" scan \
-d "$DOMAINS" \
-p "$PROTO" \
--timeout "$TIMEOUT" \
--dns "$DNS_MODE" \
--top 20 \
--auto

REPORT="$(ls -t *_report_vanilla.txt 2>/dev/null | head -1)"
DATE="$(date +%Y-%m-%d_%H-%M-%S)"
SAFE="$(echo "$DOMAINS" | tr ', ' '_')"
OUTPUT_FILE="/root/${DATE}_${SAFE}_quick.txt"

if [ -f "$REPORT" ]; then
    TOTAL=$(grep "OK vanilla report:" "$REPORT" | head -1 | sed 's/.* \([0-9]\+\) strategies.*/\1/')
    
    {
        echo "========================================="
        echo "  БЫСТРЫЙ ПОИСК (НЕПРОВЕРЕННЫЕ СТРАТЕГИИ)"
        echo "========================================="
        echo "Дата    : $DATE"
        echo "Домен   : $DOMAINS"
        echo "Протокол: $PROTO"
        echo "Потоки  : $WORKERS"
        echo "Таймаут : $TIMEOUT"
        echo "========================================="
        echo ""
    } > "$OUTPUT_FILE"
    
    grep "nfqws2" "$REPORT" | sed 's/^[^:]*: //' | head -20 >> "$OUTPUT_FILE"
    COUNT=$(grep "nfqws2" "$REPORT" | head -20 | wc -l)
    
    printf "\n${GREEN}✓ Отчёт сохранён:${NC} $OUTPUT_FILE\n"
    printf "\n${CYAN}Всего найдено стратегий:${NC} ${YELLOW}%s${NC}\n" "${TOTAL:-$COUNT}"
    printf "${CYAN}Показано в отчёте:${NC} ${YELLOW}%s${NC}\n" "$COUNT"
    
    rm -f "$REPORT"
else
    printf "\n${RED}Отчёт не создан.${NC}\n"
    printf "\n${YELLOW}Возможные причины:${NC}\n"
    printf "  - Домен не резолвится (нет DNS записи)\n"
    printf "  - Домен выдаёт фейковый IP (подмена DNS)\n"
    printf "  - Проблемы с сетью\n"
fi

zapret_start

printf "\n${GREEN}${BOLD}Быстрый поиск завершён.${NC}\n"
pause
}

run_full_scan() {
clear
printf "${CYAN}${BOLD}=========================================${NC}\n"
printf "${CYAN}${BOLD}  Полный поиск (сканирование + проверка)${NC}\n"
printf "${CYAN}${BOLD}=========================================${NC}\n"
status_line
echo ""

zapret_stop

printf "\n${CYAN}Нажмите Enter для запуска...${NC}"
read x
clear

printf "${YELLOW}${BOLD}Сканирование...${NC}\n"
blockcheckw -w "$WORKERS" scan \
-d "$DOMAINS" \
-p "$PROTO" \
--timeout "$TIMEOUT" \
--dns "$DNS_MODE" \
--auto

REPORT="$(ls -t *_report_vanilla.txt 2>/dev/null | head -1)"

if [ -z "$REPORT" ]; then
    printf "\n${RED}${BOLD}Домен доступен без обхода или нечего проверять.${NC}\n"
    zapret_start
    pause
    return
fi

printf "\n${YELLOW}${BOLD}Проверка стратегий...${NC}\n"
echo ""

blockcheckw -w "$WORKERS" check \
--from-file "$REPORT" \
-d "$DOMAINS" \
--dns "$DNS_MODE" \
--auto

DATE="$(date +%Y-%m-%d_%H-%M-%S)"
SAFE="$(echo "$DOMAINS" | tr ', ' '_')"

CHECK_JSON="$(ls -t *_check.json 2>/dev/null | head -1)"

if [ -n "$CHECK_JSON" ]; then
    WORKING=$(sed -n 's/.*"working": *\([0-9]*\).*/\1/p' "$CHECK_JSON" | head -1)
    TOTAL=$(sed -n 's/.*"total": *\([0-9]*\).*/\1/p' "$CHECK_JSON" | head -1)
    
    [ -z "$TOTAL" ] && TOTAL=0
    [ -z "$WORKING" ] && WORKING=0
    
    printf "\n${CYAN}Проверено стратегий:${NC} ${YELLOW}%s${NC}\n" "$TOTAL"
    printf "${CYAN}Рабочих:${NC} ${GREEN}%s${NC}\n" "$WORKING"
    
    if [ "$WORKING" -gt 0 ] 2>/dev/null; then
        OUTPUT_FILE="/root/${DATE}_${SAFE}_working.txt"
        
        echo "=========================================" > "$OUTPUT_FILE"
        echo "  РАБОЧИЕ СТРАТЕГИИ" >> "$OUTPUT_FILE"
        echo "=========================================" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        sed -n '/"args": "/{s/.*"args": "//;s/",$//;s/",.*//;p}' "$CHECK_JSON" | while read line; do
            echo "nfqws2 $line"
        done >> "$OUTPUT_FILE"
        
        printf "\n${GREEN}✓ Стратегии сохранены в:${NC} $OUTPUT_FILE\n"
    else
        printf "\n${RED}Рабочих стратегий не найдено.${NC}\n"
    fi
    
    rm -f "$CHECK_JSON"
else
    printf "\n${RED}JSON отчёт не найден.${NC}\n"
fi

rm -f "$REPORT"

zapret_start

printf "\n${GREEN}${BOLD}Полный поиск завершён.${NC}\n"
pause
}

run_universal_scan() {
clear
printf "${CYAN}${BOLD}=========================================${NC}\n"
printf "${CYAN}${BOLD}  Универсальный поиск (несколько доменов)${NC}\n"
printf "${CYAN}${BOLD}=========================================${NC}\n"
status_line
echo ""

printf "${CYAN}Введите домены через пробел (или нажмите Enter для использования текущих):${NC}\n"
printf "Текущие: ${GREEN}$DOMAINS${NC}\n"
printf "→ "
read -r UNIVERSAL_DOMAINS
if [ -z "$UNIVERSAL_DOMAINS" ]; then
    UNIVERSAL_DOMAINS="$DOMAINS"
    printf "${CYAN}Используются текущие домены: ${GREEN}$UNIVERSAL_DOMAINS${NC}\n"
else
    printf "${CYAN}Будут использованы домены: ${GREEN}$UNIVERSAL_DOMAINS${NC}\n"
fi

TMP_DOMAIN_FILE="/tmp/universal_domains_$$.txt"
echo "$UNIVERSAL_DOMAINS" | tr ' ' '\n' > "$TMP_DOMAIN_FILE"

DATE="$(date +%Y-%m-%d_%H-%M-%S)"
OUTPUT_JSON="/root/universal_${DATE}.json"
OUTPUT_TXT="/root/universal_${DATE}.txt"

printf "\n${YELLOW}→ Запуск универсального поиска...${NC}\n"
printf "${DIM}Это может занять длительное время.${NC}\n\n"

WAS_RUNNING=0
if [ -x /etc/init.d/zapret2 ]; then
    if /etc/init.d/zapret2 status 2>/dev/null | grep -q "running"; then
        WAS_RUNNING=1
        printf "${YELLOW}Останавливаем zapret2...${NC}\n"
        /etc/init.d/zapret2 stop >/dev/null 2>&1
        sleep 2
        printf "${GREEN}zapret2 остановлен${NC}\n"
    else
        printf "${CYAN}zapret2 не запущен, пропускаем остановку.${NC}\n"
    fi
fi

blockcheckw universal \
    --domain-list "$TMP_DOMAIN_FILE" \
    -p "$PROTO" \
    --dns "$DNS_MODE" \
    --auto \
    -o "$OUTPUT_JSON"

if [ "$WAS_RUNNING" = "1" ]; then
    printf "\n${YELLOW}Запускаем zapret2...${NC}\n"
    /etc/init.d/zapret2 start >/dev/null 2>&1
    sleep 2
    printf "${GREEN}zapret2 запущен${NC}\n"
else
    printf "\n${CYAN}zapret2 не был остановлен скриптом, пропускаем запуск.${NC}\n"
fi

if [ ! -f "$OUTPUT_JSON" ]; then
    printf "\n${RED}Ошибка: файл с результатами не создан.${NC}\n"
    rm -f "$TMP_DOMAIN_FILE"
    pause
    return
fi

# Подсчёт стратегий через jq
if command -v jq >/dev/null 2>&1; then
    STRATEGY_COUNT=$(jq '[.protocols[].strategies[]?] | length' "$OUTPUT_JSON" 2>/dev/null)
    [ -z "$STRATEGY_COUNT" ] && STRATEGY_COUNT=0
else
    STRATEGY_COUNT=$(grep -c '"args":' "$OUTPUT_JSON" 2>/dev/null)
fi

printf "\n${GREEN}✓ Результат универсального поиска сохранён:${NC}\n"
printf "   JSON: ${OUTPUT_JSON}\n"
if [ "$STRATEGY_COUNT" -gt 0 ]; then
    # Создание текстового файла с командами
    if command -v jq >/dev/null 2>&1; then
        jq -r '.protocols[].strategies[]?.args' "$OUTPUT_JSON" | sed 's/^/nfqws2 /' > "$OUTPUT_TXT"
    else
        grep '"args":' "$OUTPUT_JSON" | sed 's/.*"args": "//;s/",$//;s/",.*//;s/^/nfqws2 /' > "$OUTPUT_TXT"
    fi
    printf "   TXT (команды): ${OUTPUT_TXT}\n"
fi
printf "${CYAN}Найдено универсальных стратегий: ${GREEN}%s${NC}\n" "$STRATEGY_COUNT"

if [ "$STRATEGY_COUNT" -gt 0 ]; then
    printf "${YELLOW}Желаете проверить лучшие стратегии (check) для одного из доменов? (y/N): ${NC}"
    read -r DO_CHECK
    case "$DO_CHECK" in
        y|Y|yes|Yes|YES)
            CHECK_DOMAIN=$(echo "$UNIVERSAL_DOMAINS" | awk '{print $1}')
            printf "${CYAN}Домен для проверки: ${GREEN}$CHECK_DOMAIN${NC}\n"
            printf "${CYAN}Количество проверяемых стратегий (по умолчанию 20, можно задать любое): ${NC}"
            read -r TAKE_COUNT
            [ -z "$TAKE_COUNT" ] && TAKE_COUNT=20

            printf "\n${YELLOW}→ Запуск проверки (check) для первых ${TAKE_COUNT} стратегий...${NC}\n"

            # Определяем протокол для подстановки в префикс
            CHECK_PROTO="tls13"
            case "$PROTO" in
                *tls13*) CHECK_PROTO="tls13" ;;
                *tls12*) CHECK_PROTO="tls12" ;;
                *http*)  CHECK_PROTO="http" ;;
            esac

            STRAT_FILE="/tmp/universal_strategies_$$.txt"
            # Создаём файл в формате vanilla-отчёта, который понимает check --from-file
            if command -v jq >/dev/null 2>&1; then
                jq -r ".protocols[].strategies[]?.args" "$OUTPUT_JSON" \
                | head -n "$TAKE_COUNT" \
                | sed "s/^/curl_test_https_${CHECK_PROTO} ipv4 ${CHECK_DOMAIN} : nfqws2 /" > "$STRAT_FILE"
            else
                grep '"args":' "$OUTPUT_JSON" \
                | head -n "$TAKE_COUNT" \
                | sed 's/.*"args": "//;s/",$//;s/",.*//' \
                | sed "s/^/curl_test_https_${CHECK_PROTO} ipv4 ${CHECK_DOMAIN} : nfqws2 /" > "$STRAT_FILE"
            fi

            STRAT_COUNT=$(wc -l < "$STRAT_FILE")
            if [ "$STRAT_COUNT" -gt 0 ]; then
                CHECK_WAS_RUNNING=0
                if [ -x /etc/init.d/zapret2 ]; then
                    if /etc/init.d/zapret2 status 2>/dev/null | grep -q "running"; then
                        CHECK_WAS_RUNNING=1
                        printf "${YELLOW}Останавливаем zapret2 для проверки...${NC}\n"
                        /etc/init.d/zapret2 stop >/dev/null 2>&1
                        sleep 2
                        printf "${GREEN}zapret2 остановлен${NC}\n"
                    fi
                fi

                # Запуск check
                blockcheckw check \
                    --from-file "$STRAT_FILE" \
                    -d "$CHECK_DOMAIN" \
                    --dns "$DNS_MODE" \
                    --auto \
                    --take "$TAKE_COUNT"

                if [ "$CHECK_WAS_RUNNING" = "1" ]; then
                    printf "\n${YELLOW}Запускаем zapret2...${NC}\n"
                    /etc/init.d/zapret2 start >/dev/null 2>&1
                    sleep 2
                    printf "${GREEN}zapret2 запущен${NC}\n"
                fi
                rm -f "$STRAT_FILE"

                # Сохраняем успешные стратегии из check результата
                CHECK_JSON_FILE="$(ls -t *_check.json 2>/dev/null | head -1)"
                if [ -n "$CHECK_JSON_FILE" ] && command -v jq >/dev/null 2>&1; then
                    # Извлекаем аргументы успешных стратегий (где success_rate == 1.0)
                    WORKING_COUNT=$(jq '[.strategies[]? | select(.success_rate == 1.0) ] | length' "$CHECK_JSON_FILE" 2>/dev/null)
                    if [ -n "$WORKING_COUNT" ] && [ "$WORKING_COUNT" -gt 0 ]; then
                        WORKING_FILE="/root/universal_working_${DATE}.txt"
                        jq -r '.strategies[]? | select(.success_rate == 1.0) | "nfqws2 " + .args' "$CHECK_JSON_FILE" > "$WORKING_FILE"
                        printf "\n${GREEN}✓ Проверенные рабочие стратегии сохранены: ${WORKING_FILE}${NC}\n"
                        printf "${CYAN}Количество проверенных рабочих стратегий: ${GREEN}%s${NC}\n" "$WORKING_COUNT"
                    else
                        printf "\n${RED}Рабочих стратегий не найдено.${NC}\n"
                    fi
                    rm -f "$CHECK_JSON_FILE"
                else
                    printf "\n${YELLOW}Не удалось сохранить проверенные стратегии (jq не установлен или нет JSON).${NC}\n"
                fi
            else
                printf "${RED}Не удалось извлечь стратегии для проверки.${NC}\n"
            fi
            printf "\n${GREEN}✓ Проверка завершена.${NC}\n"
            ;;
        *)
            printf "\n${CYAN}Проверка отложена. Вы можете запустить её позже вручную:${NC}\n"
            printf "  jq -r '.protocols[].strategies[]?.args' %s | head -20 | sed 's/^/nfqws2 /' > /tmp/check.txt && blockcheckw check --from-file /tmp/check.txt -d %s\n" "$OUTPUT_JSON" "$CHECK_DOMAIN"
            ;;
    esac
else
    printf "\n${CYAN}Универсальные стратегии не найдены. Проверка не требуется.${NC}\n"
fi

rm -f "$TMP_DOMAIN_FILE"
printf "\n${GREEN}${BOLD}Универсальный поиск завершён.${NC}\n"
pause
}

show_results() {
while true
do
clear
printf "${CYAN}${BOLD}=========================================${NC}\n"
printf "${CYAN}${BOLD}  Результаты поиска${NC}\n"
printf "${CYAN}${BOLD}=========================================${NC}\n"
echo ""
echo "1. Показать рабочие стратегии (один домен)"
echo "2. Показать быстрый отчёт (один домен)"
echo "3. Показать универсальные отчёты (несколько доменов)"
echo "4. Очистить все логи и отчёты"
echo "0. Назад"
echo ""
printf "Выбор: "
read S

case "$S" in
1)
    FILE="$(ls -t /root/*_working.txt 2>/dev/null | head -1)"
    if [ -z "$FILE" ]; then
        printf "${RED}Нет файлов с рабочими стратегиями.${NC}\n"
        pause
    else
        clear
        cat "$FILE"
        echo ""
        printf "${CYAN}Файл:${NC} $FILE\n"
        pause
    fi
    ;;
2)
    FILE="$(ls -t /root/*_quick.txt 2>/dev/null | head -1)"
    if [ -z "$FILE" ]; then
        printf "${RED}Нет быстрых отчётов.${NC}\n"
        pause
    else
        clear
        cat "$FILE"
        echo ""
        printf "${CYAN}Файл:${NC} $FILE\n"
        pause
    fi
    ;;
3)
    # Сначала показываем рабочие проверенные универсальные, если есть
    WORKING_FILE="$(ls -t /root/universal_working_*.txt 2>/dev/null | head -1)"
    if [ -n "$WORKING_FILE" ]; then
        clear
        printf "${CYAN}${BOLD}=========================================${NC}\n"
        printf "${CYAN}${BOLD}  УНИВЕРСАЛЬНЫЕ ПРОВЕРЕННЫЕ СТРАТЕГИИ${NC}\n"
        printf "${CYAN}${BOLD}=========================================${NC}\n"
        echo ""
        cat "$WORKING_FILE"
        echo ""
        printf "${CYAN}Файл:${NC} $WORKING_FILE\n"
        pause
    else
        # Иначе показываем обычный универсальный TXT
        TXT_FILE="$(ls -t /root/universal_*.txt 2>/dev/null | head -1)"
        JSON_FILE="$(ls -t /root/universal_*.json 2>/dev/null | head -1)"
        if [ -n "$TXT_FILE" ]; then
            clear
            printf "${CYAN}${BOLD}=========================================${NC}\n"
            printf "${CYAN}${BOLD}  УНИВЕРСАЛЬНЫЙ ОТЧЁТ (команды)${NC}\n"
            printf "${CYAN}${BOLD}=========================================${NC}\n"
            echo ""
            cat "$TXT_FILE"
            echo ""
            printf "${CYAN}Файл:${NC} $TXT_FILE\n"
            pause
        elif [ -n "$JSON_FILE" ]; then
            clear
            printf "${CYAN}${BOLD}=========================================${NC}\n"
            printf "${CYAN}${BOLD}  УНИВЕРСАЛЬНЫЙ ОТЧЁТ (JSON)${NC}\n"
            printf "${CYAN}${BOLD}=========================================${NC}\n"
            echo ""
            if command -v jq >/dev/null 2>&1; then
                jq -r '.protocols[].strategies[]?.args' "$JSON_FILE" | head -50 | sed 's/^/nfqws2 /'
                echo ""
                echo "... (первые 50)"
            else
                head -50 "$JSON_FILE"
            fi
            echo ""
            printf "${CYAN}Файл:${NC} $JSON_FILE\n"
            pause
        else
            printf "${RED}Нет универсальных отчётов.${NC}\n"
            pause
        fi
    fi
    ;;
4)
    cleanup_logs
    ;;
0) return ;;
esac
done
}

init_cfg
ln -sf "$SELF" "$LINK"

while true
do
clear
printf "${CYAN}${BOLD}==================================${NC}\n"
printf "${CYAN}${BOLD} BlockCheckW Manager v0.4.2${NC}\n"
printf "${CYAN}${BOLD}==================================${NC}\n"
printf "${CYAN}Движок:${NC} ${GREEN}${BCW_VERSION}${NC} ${CYAN}(зафиксирован)${NC}\n"
echo "1. Установить / обновить blockcheckw"
echo "2. Удалить blockcheckw + настройки"
echo "3. Быстрый поиск (только сканирование, один домен)"
echo "4. Полный поиск (сканирование + проверка, один домен)"
echo "5. Универсальный поиск (несколько доменов)"
echo "6. Настройки"
echo "7. Показать результаты"
echo "0. Выход"
printf "${CYAN}${BOLD}==================================${NC}\n"
status_line
printf "${CYAN}${BOLD}==================================${NC}\n"
printf "Выбор: "
read N

case "$N" in
1) install_bcw ;;
2) remove_all ;;
3) run_quick_scan ;;
4) run_full_scan ;;
5) run_universal_scan ;;
6) settings_menu ;;
7) show_results ;;
0) exit 0 ;;
esac
done
EOF

chmod +x /root/blockcheckw-manager.sh
ln -sf /root/blockcheckw-manager.sh /usr/bin/bcw
bcw
