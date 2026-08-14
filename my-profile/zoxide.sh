#!/usr/bin/env bash

if type zoxide &>/dev/null; then
	eval "$(zoxide init --cmd cd bash)"
fi
