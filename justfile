_default:
    just --list

init-submodules:
  git submodule update --init --recursive

test-zsh-tmux:
    cd zsh/__tests__ && ./bats/bin/bats tmux.sh.bats
