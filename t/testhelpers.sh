#!/usr/bin/env bash

# assert_pointer confirms that the pointer in the repository for $path in the
# given $ref matches the given $oid and $size.
# Note that $path is prepended with a space to match the against the start
# of path field in the ls-tree output, so be careful if your test involves
# files with spaces in their paths.
#
#   $ assert_pointer "main" "path/to/file" "some-oid" 123
assert_pointer() {
  local ref="$1"
  local path="$2"
  local oid="$3"
  local size="$4"

  gitblob=$(git ls-tree -lrz "$ref" |
    while read -r -d $'\0' x; do
      echo $x
    done |
    grep -F " $path" | cut -f 3 -d " ")

  actual=$(git cat-file -p $gitblob)
  expected=$(pointer $oid $size)

  if [ "$expected" != "$actual" ]; then
    exit 1
  fi
}

# refute_pointer confirms that the file in the repository for $path in the
# given $ref is _not_ a pointer.
# Note that $path is prepended with a space to match the against the start
# of path field in the ls-tree output, so be careful if your test involves
# files with spaces in their paths.
#
#   $ refute_pointer "main" "path/to/file"
refute_pointer() {
  local ref="$1"
  local path="$2"

  gitblob=$(git ls-tree -lrz "$ref" |
    while read -r -d $'\0' x; do
      echo $x
    done |
    grep -F " $path" | cut -f 3 -d " ")

  file=$(git cat-file -p $gitblob)
  version="version https://git-lfs.github.com/spec/v[0-9]"
  oid="oid sha256:[0-9a-f]\{64\}"
  size="size [0-9]*"
  regex="$version.*$oid.*$size"

  if echo $file | grep -q "$regex"; then
    exit 1
  fi
}

# local_object_path computes the path to the local storage for an oid
# $ local_object_path "some-oid"
local_object_path() {
  local oid="$1"
  local cfg=`git lfs env | grep LocalMediaDir`
  echo "${cfg#LocalMediaDir=}/${oid:0:2}/${oid:2:2}/$oid"
}

# assert_local_object confirms that an object file is stored for the given oid &
# has the correct size
# $ assert_local_object "some-oid" size
assert_local_object() {
  local oid="$1"
  local size="$2"
  local f="$(local_object_path "$oid")"
  actualsize=$(wc -c <"$f" | tr -d '[[:space:]]')
  if [ "$size" != "$actualsize" ]; then
    exit 1
  fi
}

# refute_local_object confirms that an object file is NOT stored for an oid.
# If "$size" is given as the second argument, assert that the file exists _and_
# that it does _not_ the expected size
#
# $ refute_local_object "some-oid"
# $ refute_local_object "some-oid" "123"
refute_local_object() {
  local oid="$1"
  local size="$2"
  local f="$(local_object_path "$oid")"
  if [ -e $f ]; then
    if [ -z "$size" ]; then
      exit 1
    fi

    actual_size="$(wc -c < "$f" | awk '{ print $1 }')"
    if [ "$size" -eq "$actual_size" ]; then
      echo >&2 "fatal: expected object $oid not to have size: $size"
      exit 1
    fi
  fi
}

# delete_local_object deletes the local storage for an oid
# $ delete_local_object "some-oid"
delete_local_object() {
  local oid="$1"
  local f="$(local_object_path "$oid")"
  rm "$f"
}

# corrupt_local_object corrupts the local storage for an oid
# $ corrupt_local_object "some-oid"
corrupt_local_object() {
  local oid="$1"
  local f="$(local_object_path "$oid")"
  cp /dev/null "$f"
}


# check that the object does not exist in the git lfs server. HTTP log is
# written to http.log. JSON output is written to http.json.
#
#   $ refute_server_object "reponame" "oid"
refute_server_object() {
  local reponame="$1"
  local oid="$2"
  curl -v "$GITSERVER/$reponame.git/info/lfs/objects/batch" \
    -u "user:pass" \
    -o http.json \
    -d "{\"operation\":\"download\",\"objects\":[{\"oid\":\"$oid\"}]}" \
    -H "Accept: application/vnd.git-lfs+json" \
    -H "Content-Type: application/vnd.git-lfs+json" \
    -H "X-Check-Object: 1" \
    -H "X-Ignore-Retries: true" 2>&1 |
    tee http.log

  [ "0" = "$(grep -c "download" http.json)" ] || {
    cat http.json
    exit 1
  }
}

# Delete an object on the lfs server. HTTP log is
# written to http.log. JSON output is written to http.json.
#
#   $ delete_server_object "reponame" "oid"
delete_server_object() {
  local reponame="$1"
  local oid="$2"
  curl -v "$GITSERVER/$reponame.git/info/lfs/objects/$oid" \
    -X DELETE \
    -u "user:pass" \
    -o http.json \
    -H "Accept: application/vnd.git-lfs+json" 2>&1 |
    tee http.log

  grep "200 OK" http.log
}

# check that the object does exist in the git lfs server. HTTP log is written
# to http.log. JSON output is written to http.json.
assert_server_object() {
  local reponame="$1"
  local oid="$2"
  local refspec="$3"
  curl -v "$GITSERVER/$reponame.git/info/lfs/objects/batch" \
    -u "user:pass" \
    -o http.json \
    -d "{\"operation\":\"download\",\"objects\":[{\"oid\":\"$oid\"}],\"ref\":{\"name\":\"$refspec\"}}" \
    -H "Accept: application/vnd.git-lfs+json" \
    -H "Content-Type: application/vnd.git-lfs+json" \
    -H "X-Check-Object: 1" \
    -H "X-Ignore-Retries: true" 2>&1 |
    tee http.log
  grep "200 OK" http.log

  grep "download" http.json || {
    cat http.json
    exit 1
  }
}

# assert_remote_object() confirms that an object file with the given OID and
# size is stored in the "remote" copy of a repository
assert_remote_object() {
  local reponame="$1"
  local oid="$2"
  local size="$3"
  local destination="$(canonical_path "$REMOTEDIR/$reponame.git")"

  pushd "$destination"
    local f="$(local_object_path "$oid")"
    actualsize="$(wc -c <"$f" | tr -d '[[:space:]]')"
    [ "$size" -eq "$actualsize" ]
  popd
}

# refute_remote_object() confirms that an object file with the given OID
# is not stored in the "remote" copy of a repository
refute_remote_object() {
  local reponame="$1"
  local oid="$2"
  local destination="$(canonical_path "$REMOTEDIR/$reponame.git")"

  pushd "$destination"
    local f="$(local_object_path "$oid")"
    if [ -e $f ]; then
      exit 1
    fi
  popd
}

# Set rate limit counts on the LFS server. HTTP log is written to http.log.
#
#   $ reset_server_rate_limit "api" "direction" "reponame" "oid" "num-tokens"
set_server_rate_limit() {
  local api="$1"
  local direction="$2"
  local reponame="$3"
  local oid="$4"
  local tokens="$5"

  local query="api=$api&direction=$direction&repo=$reponame&oid=$oid&tokens=$tokens"

  curl -v "$GITSERVER/limits/?$query" 2>&1 | tee http.log

  grep "200 OK" http.log
}

check_server_lock_ssh() {
  local reponame="$1"
  local id="$2"
  local refspec="$3"
  local destination="$(canonical_path "$REMOTEDIR/$reponame.git")"

  (
    pktize_text 'version 1'
    pktize_flush
    pktize_text 'list-lock'
    pktize_text "id=$id"
    pktize_text "refname=$refname"
    pktize_flush
    pktize_text 'quit'
    pktize_flush
  ) | lfs-ssh-echo git@127.0.0.1 "git-lfs-transfer '$destination' download" 2>&1
}

# This asserts the lock path and returns the lock ID by parsing the response of
#
#   git lfs lock --json <path>
assert_lock() {
  local log="$1"
  local path="$2"

  if [ $(grep -c "\"path\":\"$path\"" "$log") -eq 0 ]; then
    echo "path '$path' not found in:"
    cat "$log"
    exit 1
  fi

  local jsonid=$(grep -oh "\"id\":\"\w\+\"" "$log")
  echo "${jsonid:3}" | tr -d \"\:
}

# assert that a lock with the given ID exists on the test server
assert_server_lock() {
  local reponame="$1"
  local id="$2"
  local refspec="$3"

  curl -v "$GITSERVER/$reponame.git/info/lfs/locks?refspec=$refspec" \
    -u "user:pass" \
    -o http.json \
    -H "Accept:application/vnd.git-lfs+json" 2>&1 |
    tee http.log

  grep "200 OK" http.log
  grep "$id" http.json || {
    cat http.json
    exit 1
  }
}

# assert that a lock with the given ID exists on the test server
assert_server_lock_ssh() {
  local reponame="$1"
  local id="$2"
  local refspec="$3"

  check_server_lock_ssh "$reponame" "$id" "$refspec" |
    tee output.log

  grep "status 200" output.log
  grep "$id" output.log || {
    cat output.log
    exit 1
  }
}

# refute that a lock with the given ID exists on the test server
refute_server_lock() {
  local reponame="$1"
  local id="$2"
  local refspec="$3"

  curl -v "$GITSERVER/$reponame.git/info/lfs/locks?refspec=$refspec" \
    -u "user:pass" \
    -o http.json \
    -H "Accept:application/vnd.git-lfs+json" 2>&1 | tee http.log

  grep "200 OK" http.log

  [ $(grep -c "$id" http.json) -eq 0 ]
}

# refute that a lock with the given ID exists on the test server
refute_server_lock_ssh() {
  local reponame="$1"
  local id="$2"
  local refspec="$3"
  local destination="$(canonical_path "$REMOTEDIR/$reponame.git")"

  check_server_lock_ssh "$reponame" "$id" "$refspec" |
    tee output.log

  grep "status 200" output.log
  if grep "$id" output.log
  then
    cat output.log
    exit 1
  fi
}

# Assert that .gitattributes contains a given attribute N times
assert_attributes_count() {
  local fileext="$1"
  local attrib="$2"
  local count="$3"

  pattern="\(*.\)\?$fileext\(.*\)$attrib"
  actual=$(grep -e "$pattern" .gitattributes | wc -l)
  if [ "$(printf "%d" "$actual")" != "$count" ]; then
    echo "wrong number of $attrib entries for $fileext"
    echo "expected: $count actual: $actual"
    cat .gitattributes
    exit 1
  fi
}

assert_file_writeable() {
  ls -l "$1" | grep -e "^-rw"
}

refute_file_writeable() {
  ls -l "$1" | grep -e "^-r-"
}

git_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

dot_git_dir() {
  echo "$(git_root)/.git"
}

assert_hooks() {
  local git_root="$1"

  if [ -z "$git_root" ]; then
    echo >&2 "fatal: (assert_hooks) not in git repository"
    exit 1
  fi

  [ -x "$git_root/hooks/post-checkout" ]
  [ -x "$git_root/hooks/post-commit" ]
  [ -x "$git_root/hooks/post-merge" ]
  [ -x "$git_root/hooks/pre-push" ]
}

assert_clean_status() {
  status="$(git status)"
  echo "$status" | grep "working tree clean" || {
    echo $status
    git lfs status
  }
}

# pointer returns a string Git LFS pointer file.
#
#   $ pointer abc-some-oid 123 <version>
#   > version ...
pointer() {
  local oid=$1
  local size=$2
  local version=${3:-https://git-lfs.github.com/spec/v1}
  printf "version %s
oid sha256:%s
size %s
" "$version" "$oid" "$size"
}

# wait_for_file simply sleeps until a file exists.
#
#   $ wait_for_file "path/to/upcoming/file"
wait_for_file() {
  local filename="$1"
  n=0
  wait_time=1
  while [ $n -lt 17 ]; do
    if [ -s $filename ]; then
      return 0
    fi

    sleep $wait_time
    n=`expr $n + 1`
    if [ $wait_time -lt 4 ]; then
      wait_time=`expr $wait_time \* 2`
    fi
  done

  echo "$filename did not appear after 60 seconds."
  return 1
}

# setup_remote_repo initializes a bare Git repository that is accessible through
# the test Git server. The `pwd` is set to the repository's directory, in case
# further commands need to be run. This server is running for every test in an
# integration run, so every test file should setup its own remote repository to
# avoid conflicts.
#
#   $ setup_remote_repo "some-name"
#
setup_remote_repo() {
  local reponame="$1"
  echo "set up remote git repository: $reponame"
  repodir="$REMOTEDIR/$reponame.git"
  mkdir -p "$repodir"
  cd "$repodir"
  git init --bare
  git config http.receivepack true
  git config receive.denyCurrentBranch ignore
}

# creates a bare remote repository for a local clone. Useful to test pushing to
# a fresh remote server.
#
#   $ setup_alternate_remote "$reponame-whatever"
#   $ setup_alternate_remote "$reponame-whatever" "other-remote-name"
#
setup_alternate_remote() {
  local newRemoteName=$1
  local remote=${2:-origin}

  wd=`pwd`

  setup_remote_repo "$newRemoteName"
  cd $wd
  git remote rm "$remote"
  git remote add "$remote" "$GITSERVER/$newRemoteName"
}

# clone_repo clones a repository from the test Git server to the subdirectory
# $dir under $TRASHDIR. setup_remote_repo() needs to be run first. Output is
# written to clone.log.
clone_repo() {
  cd "$TRASHDIR"

  local reponame="$1"
  local dir="$2"
  echo "clone local git repository $reponame to $dir"
  git clone "$GITSERVER/$reponame" "$dir" 2>&1 | tee clone.log

  if [ "0" -ne "${PIPESTATUS[0]}" ]; then
    return 1
  fi

  cd "$dir"
  mv ../clone.log .

  git config credential.helper lfstest
}

# clone_repo_url clones a Git repository to the subdirectory $dir under $TRASHDIR.
# setup_remote_repo() needs to be run first. Output is written to clone.log.
clone_repo_url() {
  cd "$TRASHDIR"

  local repo="$1"
  local dir="$2"
  echo "clone git repository $repo to $dir"
  git clone "$repo" "$dir" 2>&1 | tee clone.log

  if [ "0" -ne "${PIPESTATUS[0]}" ]; then
    return 1
  fi

  cd "$dir"
  mv ../clone.log .

  git config credential.helper lfstest
}

# clone_repo_ssl clones a repository from the test Git server to the subdirectory
# $dir under $TRASHDIR, using the SSL endpoint.
# setup_remote_repo() needs to be run first. Output is written to clone_ssl.log.
clone_repo_ssl() {
  cd "$TRASHDIR"

  local reponame="$1"
  local dir="$2"
  echo "clone local git repository $reponame to $dir"
  git clone "$SSLGITSERVER/$reponame" "$dir" 2>&1 | tee clone_ssl.log

  if [ "0" -ne "${PIPESTATUS[0]}" ]; then
    return 1
  fi

  cd "$dir"
  mv ../clone_ssl.log .

  git config credential.helper lfstest
}

# clone_repo_clientcert clones a repository from the test Git server to the subdirectory
# $dir under $TRASHDIR, using the client cert endpoint.
# setup_remote_repo() needs to be run first. Output is written to clone_client_cert.log.
clone_repo_clientcert() {
  cd "$TRASHDIR"

  local reponame="$1"
  local dir="$2"
  echo "clone $CLIENTCERTGITSERVER/$reponame to $dir"
  git clone "$CLIENTCERTGITSERVER/$reponame" "$dir" 2>&1 | tee clone_client_cert.log

  if [ "0" -ne "${PIPESTATUS[0]}" ]; then
    return 1
  fi

  cd "$dir"
  mv ../clone_client_cert.log .

  git config credential.helper lfstest
}

# setup_remote_repo_with_file creates a remote repo, clones it locally, commits
# a file tracked by LFS, and pushes it to the remote:
#
#     setup_remote_repo_with_file "reponame" "filename"
setup_remote_repo_with_file() {
  local reponame="$1"
  local filename="$2"
  local dirname="$(dirname "$filename")"

  setup_remote_repo "$reponame"
  clone_repo "$reponame" "clone_$reponame"

  mkdir -p "$dirname"

  git lfs track "$filename"
  echo "$filename" > "$filename"
  git add .gitattributes $filename
  git commit -m "add $filename" | tee commit.log

  grep "main (root-commit)" commit.log
  grep "2 files changed" commit.log
  grep "create mode 100644 $filename" commit.log
  grep "create mode 100644 .gitattributes" commit.log

  git push origin main 2>&1 | tee push.log
  grep "main -> main" push.log
}

# substring_position returns the position of a substring in a 1-indexed search
# space.
#
#     [ "$(substring_position "foo bar baz" "baz")" -eq "9" ]
substring_position() {
  local str="$1"
  local substr="$2"

  # 1) Print the string...
  # 2) Remove the substring and everything after it
  # 3) Count the number of characters (bytes) left, i.e., the offset of the
  #    string we were looking for.

  echo "$str" \
    | sed "s/$substr.*$//" \
    | wc -c
}

# repo_endpoint returns the LFS endpoint for a given server and repository.
#
#     [ "$GITSERVER/example/repo.git/info/lfs" = "$(repo_endpoint $GITSERVER example-repo)" ]
repo_endpoint() {
  local server="$1"
  local repo="$2"

  echo "$server/$repo.git/info/lfs"
}

# write_creds_file writes credentials to a file iff it doesn't exist.
write_creds_file() {
  local creds="$1"
  local file="$2"

  if [ ! -f "$file" ]
  then
    printf "%s" "$creds" > "$file"
  fi
}

setup_creds() {
  mkdir -p "$CREDSDIR"
  write_creds_file ":user:pass" "$CREDSDIR/127.0.0.1"
}

# setup initializes the clean, isolated environment for integration tests.
setup() {
  cd "$ROOTDIR"

  if [ ! -d "$REMOTEDIR" ]; then
    mkdir "$REMOTEDIR"
  fi

  echo "# Git LFS: ${LFS_BIN:-$(command -v git-lfs)}"
  git lfs version | sed -e 's/^/# /g'
  git version | sed -e 's/^/# /g'

  LFSTEST_URL="$LFS_URL_FILE" \
  LFSTEST_SSL_URL="$LFS_SSL_URL_FILE" \
  LFSTEST_CLIENT_CERT_URL="$LFS_CLIENT_CERT_URL_FILE" \
  LFSTEST_DIR="$REMOTEDIR" \
  LFSTEST_CERT="$LFS_CERT_FILE" \
  LFSTEST_CLIENT_CERT="$LFS_CLIENT_CERT_FILE" \
  LFSTEST_CLIENT_KEY="$LFS_CLIENT_KEY_FILE" \
  LFSTEST_CLIENT_KEY_ENCRYPTED="$LFS_CLIENT_KEY_FILE_ENCRYPTED" \
    lfstest-count-tests increment

  wait_for_file "$LFS_URL_FILE"
  wait_for_file "$LFS_SSL_URL_FILE"
  wait_for_file "$LFS_CLIENT_CERT_URL_FILE"
  wait_for_file "$LFS_CERT_FILE"
  wait_for_file "$LFS_CLIENT_CERT_FILE"
  wait_for_file "$LFS_CLIENT_KEY_FILE"
  wait_for_file "$LFS_CLIENT_KEY_FILE_ENCRYPTED"

  LFS_CLIENT_CERT_URL=`cat $LFS_CLIENT_CERT_URL_FILE`

  # Set up the initial git config and osx keychain if applicable
  HOME="$TESTHOME"
  if [ ! -d "$HOME" ]; then
    mkdir "$HOME"
  fi

  # do not let Git use a different configuration file
  unset GIT_CONFIG
  unset XDG_CONFIG_HOME

  if [ ! -f $HOME/.gitconfig ]; then
    git lfs install --skip-repo
    git config --global credential.usehttppath true
    git config --global credential.helper lfstest
    git config --global user.name "Git LFS Tests"
    git config --global user.email "git-lfs@example.com"
    git config --global http.sslcainfo "$LFS_CERT_FILE"
    git config --global init.defaultBranch main
  fi | sed -e 's/^/# /g'

  # setup the git credential password storage
  setup_creds

  echo "#"
  echo "# HOME: $HOME"
  echo "# TMP: $TMPDIR"
  echo "# CREDS: $CREDSDIR"
  echo "# lfstest-gitserver:"
  echo "#   LFSTEST_URL=$LFS_URL_FILE"
  echo "#   LFSTEST_SSL_URL=$LFS_SSL_URL_FILE"
  echo "#   LFSTEST_CLIENT_CERT_URL=$LFS_CLIENT_CERT_URL_FILE ($LFS_CLIENT_CERT_URL)"
  echo "#   LFSTEST_CERT=$LFS_CERT_FILE"
  echo "#   LFSTEST_CLIENT_CERT=$LFS_CLIENT_CERT_FILE"
  echo "#   LFSTEST_CLIENT_KEY=$LFS_CLIENT_KEY_FILE"
  echo "#   LFSTEST_CLIENT_KEY_ENCRYPTED=$LFS_CLIENT_KEY_FILE_ENCRYPTED"
  echo "#   LFSTEST_DIR=$REMOTEDIR"
}

# shutdown cleans the $TRASHDIR and shuts the test Git server down.
shutdown() {
  # every t/t-*.sh file should cleanup its trashdir
  [ -z "$KEEPTRASH" ] && rm -rf "$TRASHDIR"

  LFSTEST_DIR="$REMOTEDIR" \
  LFS_URL_FILE="$LFS_URL_FILE" \
    lfstest-count-tests decrement

  # delete entire lfs test root if we created it (double check pattern)
  if [ -z "$KEEPTRASH" ] && [ "$RM_GIT_LFS_TEST_DIR" = "yes" ] && [[ $GIT_LFS_TEST_DIR == *"$TEMPDIR_PREFIX"* ]]; then
    rm -rf "$GIT_LFS_TEST_DIR"
  fi
}

tap_show_plan() {
  local tests="$1"

  printf "1..%i\n" "$tests"
}

skip_if_root_or_admin() {
  local test_description="$1"

  if [ "$IS_WINDOWS" -eq 1 ]; then
    # The sfc.exe (System File Checker) command should be available on all
    # modern Windows systems, and when run without arguments, returns help
    # text, but only when the user has Administrator privileges.  By checking
    # the help text, if any, for the /SCANNOW (i.e., "scan now") option
    # common to all versions of the command, we can determine if the
    # current user has Administrator privileges.
    #
    # Adapted from: https://stackoverflow.com/a/58846650
    #               https://stackoverflow.com/a/21295806
    SFC=$(sfc | tr -d '\0' | grep "SCANNOW")
    if [ -n "$SFC" ]; then
      printf "skip: '%s' test requires non-administrator privileges\n" \
        "$test_description"
      exit 0
    fi
  elif [ "$EUID" -eq 0 ]; then
    printf "skip: '%s' test requires non-root user\n" "$test_description"
    exit 0
  fi
}

ensure_git_version_isnt() {
  local expectedComparison=$1
  local version=$2

  local gitVersion=$(git version | cut -d" " -f3)

  set +e
  compare_version $gitVersion $version
  result=$?
  set -e

  if [[ $result == $expectedComparison ]]; then
    echo "skip: $0 (git version $(comparison_to_operator $expectedComparison) $version)"
    exit
  fi
}

VERSION_EQUAL=0
VERSION_HIGHER=1
VERSION_LOWER=2

# Compare $1 and $2 and return VERSION_EQUAL / VERSION_LOWER / VERSION_HIGHER
compare_version() {
    if [[ $1 == $2 ]]
    then
        return $VERSION_EQUAL
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return $VERSION_HIGHER
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return $VERSION_LOWER
        fi
    done
    return $VERSION_EQUAL
}

comparison_to_operator() {
  local comparison=$1
  if [[ $1 == $VERSION_EQUAL ]]; then
    echo "=="
  elif [[ $1 == $VERSION_HIGHER ]]; then
    echo ">"
  elif [[ $1 == $VERSION_LOWER ]]; then
    echo "<"
  else
    echo "???"
  fi
}

# Calculate the object ID from the string passed as the argument
calc_oid() {
  printf "$1" | $SHASUM | cut -f 1 -d " "
}

# Calculate the object ID from the file passed as the argument
calc_oid_file() {
  $SHASUM "$1" | cut -f 1 -d " "
}

# Get a date string with an offset
# Args: One or more date offsets of the form (regex) "[+-]\d+[dmyHM]"
# e.g. +1d = 1 day forward from today
#      -5y = 5 years before today
# Example call:
#   D=$(get_date +1y +1m -5H)
# returns date as string in RFC3339 format ccyy-mm-ddThh:MM:ssZ
# note returns in UTC time not local time hence Z and not +/-
get_date() {
  # Wrapped because BSD (inc OSX) & GNU 'date' functions are different
  # on Windows under Git Bash it's GNU
  if date --version >/dev/null 2>&1 ; then # GNU
    ARGS=""
    for var in "$@"
    do
        # GNU offsets are more verbose
        unit=${var: -1}
        val=${var:0:${#var}-1}
        case "$unit" in
          d) unit="days" ;;
          m) unit="months" ;;
          y) unit="years"  ;;
          H) unit="hours"  ;;
          M) unit="minutes" ;;
        esac
        ARGS="$ARGS $val $unit"
    done
    date -d "$ARGS" -u +%Y-%m-%dT%TZ
  else # BSD
    ARGS=""
    for var in "$@"
    do
        ARGS="$ARGS -v$var"
    done
    date $ARGS -u +%Y-%m-%dT%TZ
  fi
}

# escape any instance of '\' with '\\' on Windows
escape_path() {
  local unescaped="$1"
  if [ $IS_WINDOWS -eq 1 ]; then
    printf '%s' "${unescaped//\\/\\\\}"
  else
    printf '%s' "$unescaped"
  fi
}

# As native_path but escape all backslash characters to "\\"
native_path_escaped() {
  local unescaped=$(native_path "$1")
  escape_path "$unescaped"
}

# native_path_list_separator prints the operating system-specific path list
# separator.
native_path_list_separator() {
  if [ "$IS_WINDOWS" -eq 1 ]; then
    printf ";";
  else
    printf ":";
  fi
}

# canonical_path prints the native path name in a canonical form, as if
# realpath(3) were called on it.
canonical_path() {
  printf "%s" "$(lfstest-realpath "$(native_path "$1")")"
}

# canonical_path_escaped prints the native path name in a canonical form, as if
# realpath(3) were called on it, and then escapes it.
canonical_path_escaped() {
  printf "%s" "$(escape_path "$(lfstest-realpath "$(native_path "$1")")")"
}

cat_end() {
  if [ $IS_WINDOWS -eq 1 ]; then
    printf '^M$'
  else
    printf '$'
  fi
}

# Compare 2 lists which are newline-delimited in a string, ignoring ordering and blank lines
contains_same_elements() {
  # Remove blank lines then sort
  diff -u <(printf '%s' "$1" | grep -v '^$' | sort) <(printf '%s' "$2" | grep -v '^$' | sort)
}

is_stdin_attached() {
  test -t0
  echo $?
}

has_test_dir() {
  if [ -z "$GIT_LFS_TEST_DIR" ]; then
    echo "No GIT_LFS_TEST_DIR. Skipping..."
    exit 0
  fi
}

add_symlink() {
  local src=$1
  local dest=$2

  prefix=`git rev-parse --show-prefix`
  hashsrc=`printf "$src" | git hash-object -w --stdin`

  git update-index --add --cacheinfo 120000 "$hashsrc" "$prefix$dest"
  git checkout -- "$dest"
}

urlify() {
  if [ "$IS_WINDOWS" -eq 1 ]
  then
    local prefix="" path="$(canonical_path "$1")"
    if echo "$path" | grep -qsv "^/"
    then
      prefix="/"
    fi
    echo "$prefix$path" | sed -e 's,\\,/,g' -e 's,:,%3a,g' -e 's, ,%20,g'
  else
    echo "$1"
  fi
}

setup_pure_ssh() {
  export PATH="$ROOTDIR/t/scutiger/bin:$PATH"
  if ! command -v git-lfs-transfer >/dev/null 2>&1
  then
    if [ -z "$CI" ] || [ -n "$TEST_SKIP_LFS_TRANSFER" ]
    then
      echo "No git-lfs-transfer.  Skipping..."
      exit 0
    else
      echo "No git-lfs-transfer.  Failing.."
      exit 1
    fi
  elif [ "$GIT_DEFAULT_HASH" = sha256 ]
  then
      # Scutiger's git-lfs-transfer uses libgit2, which doesn't yet do SHA-256
      # repos.
      echo "Using SHA-256 repositories.  Skipping..."
      exit 0
  fi
}

ssh_remote() {
  local reponame="$1"
  local destination=$(urlify "$(canonical_path "$REMOTEDIR/$reponame.git")")
  # Prepend a slash iff it lacks one.  Windows compatibiity.
  [ -z "${destination##/*}" ] || destination="/$destination"
  echo "ssh://git@127.0.0.1$destination"
}

# Create a pkt-line message from s, which is an argument string to printf(1).
pktize() {
  local s="$1"
  local len=$(printf "$s" | wc -c)
  printf "%04x$s" $((len + 4))
}

pktize_text() {
  local s="$1"
  pktize "$s"'\n'
}

pktize_delim() {
  printf '0001'
}

pktize_flush() {
  printf '0000'
}
