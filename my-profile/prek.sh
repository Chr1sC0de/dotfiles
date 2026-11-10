#!/usr/bin/env bash

if [[ $- == *i* ]] && type prek &>/dev/null; then
	source <(prek util generate-shell-completion bash)
fi
