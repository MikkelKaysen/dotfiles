# Personal aliases & functions. Scopes live in <scope>.aliases.zsh /
# <scope>.functions.zsh — add a scope by adding a matching file.

for _pf in ${0:h}/*.functions.zsh(N) ${0:h}/*.aliases.zsh(N); do
  source ${_pf}
done
unset _pf
