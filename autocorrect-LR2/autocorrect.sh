#!/bin/bash
# LR2
# обработка текстовой информации с использованием регулярных выражений

VERSION="1.0"
AUTHOR="Лабораторная работа 3 - Обработка текстовой информации"
DEFAULT_ENCODING="UTF-8"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

LOG_FILE="autocorrect_$(date +%Y%m%d_%H%M%S).log"

log_message() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

show_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}   Автокорректор заглавных букв${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "ОС: $(lsb_release -d | cut -f2)"
    echo -e "Версия: $VERSION"
    echo -e "Лог файл: $LOG_FILE"
    echo -e "${BLUE}========================================${NC}\n"
}

check_dependencies() {
    local dependencies=("sed" "awk" "iconv" "file" "dos2unix")
    local missing=()
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_message "Установка недостающих зависимостей..." "WARNING"
        sudo apt-get update
        for dep in "${missing[@]}"; do
            log_message "Установка $dep..." "WARNING"
            sudo apt-get install -y "$dep" 2>/dev/null || {
                echo -e "${RED}Ошибка: Не удалось установить $dep${NC}"
                exit 1
            }
        done
    fi
}

preprocess_file() {
    local input_file="$1"
    local temp_file="$2"
    
    # удаление \r
    dos2unix -q "$input_file" 2>/dev/null || tr -d '\r' < "$input_file" > "$temp_file.1"
    
    # преобразование в UTF-8
    local encoding=$(file -bi "$temp_file.1" 2>/dev/null | sed -n 's/.*charset=//p' | tr '[:lower:]' '[:upper:]')
    
    case "$encoding" in
        "UTF-8"|"ASCII")
            cp "$temp_file.1" "$temp_file.2"
            ;;
        "WINDOWS-1251"|"CP1251")
            iconv -f CP1251 -t UTF-8 "$temp_file.1" > "$temp_file.2"
            ;;
        "KOI8-R")
            iconv -f KOI8-R -t UTF-8 "$temp_file.1" > "$temp_file.2"
            ;;
        "ISO-8859-5")
            iconv -f ISO-8859-5 -t UTF-8 "$temp_file.1" > "$temp_file.2"
            ;;
        *)
            # Пробуем UTF-8, если не распознали
            cp "$temp_file.1" "$temp_file.2"
            ;;
    esac
    
    # удаление BOM
    sed '1s/^\xEF\xBB\xBF//' "$temp_file.2" > "$temp_file"
    
    # очистка временных файлов
    rm -f "$temp_file.1" "$temp_file.2"
    
    echo "$encoding"
}

autocorrect_sed() {
    local input_file="$1"
    local output_file="$2"
    
    log_message "Начало обработки файла: $input_file" "INFO"
    
    # временный файл для обработки
    local temp_input=$(mktemp)
    local encoding=$(preprocess_file "$input_file" "$temp_input")
    
    log_message "Определена кодировка: ${encoding:-UTF-8}" "INFO"
    
    # sed
    
    # первая буква в файле
    sed -i '1s/^\([[:lower:]]\)/\U\1/' "$temp_input"
    
    # после . ! ? с пробелом
    sed -i ':a;N;$!ba;s/\([.!?]\) \([[:lower:]]\)/\1 \U\2/g' "$temp_input"
    
    # после . ! ? с переносом строки
    sed -i ':a;N;$!ba;s/\([.!?]\)\n\([[:lower:]]\)/\1\n\U\2/g' "$temp_input"
    
    # для русских букв (после . ! ? с пробелом)
    sed -i ':a;N;$!ba;s/\([.!?]\) \([а-я]\)/\1 \U\2/g' "$temp_input"
    
    # для русских букв (после . ! ? с переносом строки)
    sed -i ':a;N;$!ba;s/\([.!?]\)\n\([а-я]\)/\1\n\U\2/g' "$temp_input"
    
    # многоточие (...)
    sed -i 's/\.\.\. \([[:lower:]]\)/... \U\1/g' "$temp_input"
    sed -i 's/\.\.\.\n\([[:lower:]]\)/...\n\U\1/g' "$temp_input"
    
    # результат в выходной файл
    cp "$temp_input" "$output_file"
    
    count_changes "$input_file" "$output_file"
    
    rm -f "$temp_input"
    
    log_message "Обработка завершена. Результат в: $output_file" "SUCCESS"
}

autocorrect_awk() {
    local input_file="$1"
    local output_file="$2"
    
    log_message "Обработка с использованием AWK..." "INFO"
    
    awk '
    BEGIN {
        prev_punct = 1  # Начало текста считается как конец предложения
        RS = "\n"       # Разделитель записей - новая строка
    }
    
    {
        line = $0
        result = ""
        
        for (i = 1; i <= length(line); i++) {
            char = substr(line, i, 1)
            
            # Если предыдущий символ был знаком конца предложения и текущий - буква
            if (prev_punct && char ~ /[a-zA-Zа-яА-Я]/) {
                # Преобразуем в верхний регистр
                char = toupper(char)
                prev_punct = 0
            }
            
            result = result char
            
            # Проверяем, является ли текущий символ знаком конца предложения
            if (char ~ /[.!?]/) {
                # Проверяем, что это не часть числа (например, 3.14)
                if (i > 1 && i < length(line)) {
                    prev_char = substr(line, i-1, 1)
                    next_char = substr(line, i+1, 1)
                    if (!(prev_char ~ /[0-9]/ && next_char ~ /[0-9]/)) {
                        prev_punct = 1
                    }
                } else {
                    prev_punct = 1
                }
            } else if (char !~ /[[:space:]]/) {
                prev_punct = 0
            }
        }
        
        print result
    }
    ' "$input_file" > "$output_file"
    
    log_message "AWK обработка завершена" "SUCCESS"
}

count_changes() {
    local original="$1"
    local corrected="$2"
    
    local changes=$(diff --unchanged-line-format='' \
                         --old-line-format='' \
                         --new-line-format='%dn\n' \
                         "$original" "$corrected" | wc -l)
    
    log_message "Найдено изменений: $changes" "INFO"
    
    if [ "$changes" -gt 0 ]; then
        echo -e "\n${YELLOW}Примеры изменений:${NC}"
        echo -e "${BLUE}=================${NC}"
        
        local count=0
        while IFS= read -r line_num && [ "$count" -lt 3 ]; do
            if [ -n "$line_num" ]; then
                local orig_line=$(sed -n "${line_num}p" "$original")
                local corr_line=$(sed -n "${lineNum}p" "$corrected")
                
                echo -e "${RED}Строка $line_num:${NC}"
                echo -e "  Было: ${orig_line:0:50}"
                echo -e "  Стало: ${corr_line:0:50}"
                echo ""
                ((count++))
            fi
        done < <(diff --unchanged-line-format='' \
                      --old-line-format='' \
                      --new-line-format='%dn\n' \
                      "$original" "$corrected" | head -3)
    fi
}

create_test_file() {
    local test_file="$1"
    
    cat > "$test_file" << 'EOF'
это тестовый файл для проверки автокорректора.
в нем содержатся различные примеры предложений!
правильно ли работает программа? давайте проверим.
числа вроде 3.14 не должны влиять на обработку.
также 12.5 и 100.0 - это обычные числа.

после пустой строки предложение должно начинаться с заглавной.
обратите внимание! это важно.
а что насчет такого случая?
или такого!

вот пример с переносом строки.
начало нового предложения.
еще один пример!
и последний.
EOF

    log_message "Создан тестовый файл: $test_file" "INFO"
}

show_menu() {
    clear
    show_header
    
    echo -e "${GREEN}Меню:${NC}"
    echo -e "1. Обработать файл (sed)"
    echo -e "2. Обработать файл (awk)"
    echo -e "3. Создать тестовый файл"
    echo -e "4. Сравнить методы обработки"
    echo -e "5. Показать логи"
    echo -e "6. Очистить логи"
    echo -e "7. Выход"
    echo ""
}

compare_methods() {
    local test_file="compare_test.txt"
    create_test_file "$test_file"
    
    local sed_output="sed_output.txt"
    local awk_output="awk_output.txt"
    
    echo -e "\n${YELLOW}Сравнение методов обработки:${NC}"
    echo -e "${BLUE}============================${NC}"
    
    # sed
    echo -e "\n${GREEN}1. Обработка с помощью SED:${NC}"
    autocorrect_sed "$test_file" "$sed_output"
    
    # awk
    echo -e "\n${GREEN}2. Обработка с помощью AWK:${NC}"
    autocorrect_awk "$test_file" "$awk_output"

    echo -e "\n${GREEN}3. Сравнение результатов:${NC}"
    if diff -q "$sed_output" "$awk_output" > /dev/null; then
        echo -e "${GREEN}✓ Результаты идентичны${NC}"
    else
        echo -e "${RED}✗ Результаты отличаются${NC}"
        diff --brief "$sed_output" "$awk_output"
    fi
    
    echo -e "\n${GREEN}Результат обработки (первые 10 строк):${NC}"
    echo -e "${BLUE}Исходный файл:${NC}"
    head -10 "$test_file"
    echo -e "\n${BLUE}После обработки (sed):${NC}"
    head -10 "$sed_output"
    
    rm -f "$test_file" "$sed_output" "$awk_output"
    
    read -p "Нажмите Enter для продолжения..."
}

main() {
    if [ "$EUID" -eq 0 ]; then 
        log_message "Внимание: скрипт запущен от имени root!" "WARNING"
    fi
    
    check_dependencies
    
    while true; do
        show_menu
        
        read -p "Выберите действие (1-7): " choice
        
        case $choice in
            1)
                read -p "Введите путь к входному файлу: " input_file
                if [ -f "$input_file" ] && [ -r "$input_file" ]; then
                    read -p "Введите путь для выходного файла (по умолчанию: output.txt): " output_file
                    output_file="${output_file:-output.txt}"
                    autocorrect_sed "$input_file" "$output_file"
                else
                    log_message "Ошибка: файл не существует или недоступен для чтения" "ERROR"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            2)
                read -p "Введите путь к входному файлу: " input_file
                if [ -f "$input_file" ] && [ -r "$input_file" ]; then
                    read -p "Введите путь для выходного файла (по умолчанию: awk_output.txt): " output_file
                    output_file="${output_file:-awk_output.txt}"
                    autocorrect_awk "$input_file" "$output_file"
                else
                    log_message "Ошибка: файл не существует или недоступен для чтения" "ERROR"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            3)
                create_test_file "test_input.txt"
                echo -e "${GREEN}Тестовый файл создан: test_input.txt${NC}"
                read -p "Нажмите Enter для продолжения..."
                ;;
            4)
                compare_methods
                ;;
            5)
                echo -e "\n${YELLOW}Содержимое лог-файла:${NC}"
                echo -e "${BLUE}=====================${NC}"
                if [ -f "$LOG_FILE" ]; then
                    tail -20 "$LOG_FILE"
                else
                    echo "Лог-файл не существует"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            6)
                rm -f autocorrect_*.log
                LOG_FILE="autocorrect_$(date +%Y%m%d_%H%M%S).log"
                echo -e "${GREEN}Логи очищены${NC}"
                read -p "Нажмите Enter для продолжения..."
                ;;
            7)
                log_message "Завершение работы скрипта" "INFO"
                echo -e "\n${GREEN}До свидания!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный выбор. Попробуйте снова.${NC}"
                sleep 1
                ;;
        esac
    done
}

if [ $# -gt 0 ]; then
    case $1 in
        -h|--help)
            echo "Использование: $0 [опции]"
            echo ""
            echo "Опции:"
            echo "  -h, --help      Показать эту справку"
            echo "  -v, --version   Показать версию"
            echo "  -t, --test      Создать тестовый файл и обработать"
            echo "  -i, --input FILE Обработать указанный файл"
            echo "  -o, --output FILE Сохранить результат в файл"
            echo ""
            echo "Примеры:"
            echo "  $0 -i input.txt -o output.txt"
            echo "  $0 --test"
            echo "  $0              # Интерактивный режим"
            exit 0
            ;;
        -v|--version)
            echo "Автокорректор версии $VERSION"
            exit 0
            ;;
        -t|--test)
            check_dependencies
            test_file="test_$(date +%s).txt"
            create_test_file "$test_file"
            autocorrect_sed "$test_file" "test_output.txt"
            echo "Тест завершен. Результат в test_output.txt"
            rm -f "$test_file"
            exit 0
            ;;
        -i|--input)
            if [ -n "$2" ] && [ -f "$2" ]; then
                input_file="$2"
                output_file="${3:-output.txt}"
                check_dependencies
                show_header
                autocorrect_sed "$input_file" "$output_file"
            else
                echo "Ошибка: укажите входной файл"
                exit 1
            fi
            exit 0
            ;;
        *)
            echo "Неизвестная опция: $1"
            echo "Используйте $0 --help для справки"
            exit 1
            ;;
    esac
fi

main
