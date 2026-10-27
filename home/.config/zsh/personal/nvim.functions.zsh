# Launch nvim.rewrite with fully isolated config/data/state/cache
nvrr() {
  NVIM_APPNAME=nvim.rewrite nvim "$@"
}
