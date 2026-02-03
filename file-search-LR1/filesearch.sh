#!/bin/bash

set -euo pipefail

# Функция для отображения справки
show_help() {
    echo "Использование: $0 [ОПЦИИ] [ПАТТЕРН]"
    echo ""
    echo "Опции:"
    echo "  -r, --regex      Поиск по регулярному выражению"
    echo "  -h, --header     Фильтр по заголовку (первой строке файла)"
    echo "  -l, --list       Режим списка имен (по умолчанию)"
    echo "  -c, --content    Вывод содержимого с нумерацией строк"
    echo "  --help           Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 -r '.*\.txt$'              Найти все txt файлы"
    echo "  $0 -r '.*\.sh$' -c            Найти все sh файлы и показать их содержимое"
    echo "  $0 -h '#!/bin/bash' -c        Найти файлы с заголовком #!/bin/bash"
    echo "  $0 file1.txt file2.py         Найти файлы по списку имен"
}

# Переменные для хранения параметров
USE_REGEX=false
USE_HEADER=false
SHOW_CONTENT=false
HEADER_PATTERN=""
SEARCH_PATTERNS=()
CURRENT_DIR=$(pwd)

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--regex)
                USE_REGEX=true
                shift
                if [[ $# -gt 0 && ! $1 =~ ^- ]]; then
                    REGEX_PATTERN="$1"
                    shift
                else
                    echo "Ошибка: для -r требуется регулярное выражение" >&2
                    exit 1
                fi
                ;;
            -h|--header)
                USE_HEADER=true
                shift
                if [[ $# -gt 0 && ! $1 =~ ^- ]]; then
                    HEADER_PATTERN="$1"
                    shift
                else
                    echo "Ошибка: для -h требуется шаблон заголовка" >&2
                    exit 1
                fi
                ;;
            -c|--content)
                SHOW_CONTENT=true
                shift
                ;;
            -l|--list)
                SHOW_CONTENT=false
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            -*)
                echo "Неизвестная опция: $1" >&2
                show_help
                exit 1
                ;;
            *)
                SEARCH_PATTERNS+=("$1")
                shift
                ;;
        esac
    done
}

# Функция поиска файлов по регулярному выражению
search_by_regex() {
    local pattern="$1"
    find "$CURRENT_DIR" -type f -name "*" 2>/dev/null | while read -r file; do
        filename=$(basename "$file")
        if [[ "$filename" =~ $pattern ]]; then
            echo "$file"
        fi
    done
}

# Функция поиска файлов по списку имен
search_by_list() {
    for pattern in "${SEARCH_PATTERNS[@]}"; do
        find "$CURRENT_DIR" -type f -name "$pattern" 2>/dev/null
    done
}

# Функция фильтрации по заголовку
filter_by_header() {
    local pattern="$1"
    while read -r file; do
        if [[ -f "$file" && -r "$file" ]]; then
            # Читаем первую строку файла
            first_line=$(head -n 1 "$file" 2>/dev/null || echo "")
            if [[ "$first_line" == *"$pattern"* ]]; then
                echo "$file"
            fi
        fi
    done
}

# Функция для вывода содержимого файла с нумерацией
show_file_content() {
    local file="$1"
    echo ""
    echo "=== Файл: $file ==="
    echo "Размер: $(stat -c%s "$file") байт"
    echo "Изменен: $(stat -c%y "$file")"
    echo "----------------------------------------"
    
    # Нумерация строк с помощью nl
    nl -ba -w4 -s': ' "$file" 2>/dev/null || echo "Не удалось прочитать файл"
    echo "----------------------------------------"
}

# Основная функция
main() {
    parse_arguments "$@"
    
    # Проверка аргументов
    if [[ ${#SEARCH_PATTERNS[@]} -eq 0 && -z "${REGEX_PATTERN:-}" ]]; then
        echo "Ошибка: не указан шаблон для поиска" >&2
        show_help
        exit 1
    fi
    
    # Поиск файлов
    if [[ "$USE_REGEX" == true ]]; then
        file_list=$(search_by_regex "$REGEX_PATTERN")
    else
        file_list=$(search_by_list)
    fi
    
    # Фильтрация по заголовку
    if [[ "$USE_HEADER" == true ]]; then
        file_list=$(echo "$file_list" | filter_by_header "$HEADER_PATTERN")
    fi
    
    # Обработка результатов
    if [[ -z "$file_list" ]]; then
        echo "Файлы не найдены."
        exit 0
    fi
    
    count=$(echo "$file_list" | wc -l)
    echo "Найдено файлов: $count"
    echo ""
    
    if [[ "$SHOW_CONTENT" == true ]]; then
        echo "$file_list" | while read -r file; do
            show_file_content "$file"
        done
    else
        echo "Список найденных файлов:"
        echo "$file_list"
    fi
}

# Запуск основной функции
main "$@"
