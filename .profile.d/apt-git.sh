# The heroku-24 run image no longer ships a `git` binary, but Buffy shells out
# to it in Utilities#clone_repo / #change_branch. We reinstall git through the
# heroku-community/apt buildpack (see Aptfile), which unpacks it under
# /app/.apt instead of /usr. The Ubuntu git binary has /usr/lib/git-core
# compiled in as its helper directory, so without GIT_EXEC_PATH it cannot find
# git-remote-https and every clone of an https:// URL fails.
if [ -d "$HOME/.apt/usr/lib/git-core" ]; then
  export GIT_EXEC_PATH="$HOME/.apt/usr/lib/git-core"
fi

if [ -d "$HOME/.apt/usr/share/git-core/templates" ]; then
  export GIT_TEMPLATE_DIR="$HOME/.apt/usr/share/git-core/templates"
fi
