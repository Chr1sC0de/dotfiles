get_script_dir ( ) {
    echo "$(dirname -- "$(readlink -f "${BASH_SOURCE[1]}")")"

}

export -f get_script_dir