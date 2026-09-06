# .zshenv is read by every zsh. .zprofile is read only by login shells, so an
# interactive non-login shell (`kubectl exec`, `docker exec`, a terminal that
# does not start a login shell) misses it. source it here for those shells.
# .zprofile sets its own ZPROFILE_LOADED guard, so a login shell that reads
# both files still runs it only once.

if [[ -o interactive ]] && [[ -r "$HOME/.zprofile" ]]; then
  source "$HOME/.zprofile"
fi
