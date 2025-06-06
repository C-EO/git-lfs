#!/usr/bin/env bash

. "$(dirname "$0")/testlib.sh"

begin_test "ls-files"
(
  set -e

  mkdir repo
  cd repo
  git init
  git lfs track "*.dat" | grep "Tracking \"\*.dat\""
  echo "some data" > some.dat
  echo "some text" > some.txt
  echo "missing" > missing.dat
  git add missing.dat
  git commit -m "add missing file"
  [ "6bbd052ab0 * missing.dat" = "$(git lfs ls-files)" ]

  git rm missing.dat
  git add some.dat some.txt
  git commit -m "added some files, removed missing one"

  git lfs ls-files | tee ls.log
  grep some.dat ls.log
  [ `wc -l < ls.log` = 1 ]

  diff -u <(git lfs ls-files --debug) <(cat <<-EOF
filepath: some.dat
    size: 10
checkout: true
download: true
     oid: sha256 5aa03f96c77536579166fba147929626cc3a97960e994057a9d80271a736d10f
 version: https://git-lfs.github.com/spec/v1

EOF)
)
end_test

begin_test "ls-files: files in subdirectory"
(
  set -e

  reponame="ls-files-subdir"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  mkdir subdir
  missing="missing"
  missing_oid="$(calc_oid "$missing")"
  printf "%s" "$missing" > subdir/missing.dat
  git add subdir
  git commit -m "add file in subdirectory"

  contents="some data"
  oid="$(calc_oid "$contents")"
  printf "%s" "$contents" > subdir/some.dat

  echo "some text" > subdir/some.txt

  [ "${missing_oid:0:10} * subdir/missing.dat" = "$(git lfs ls-files)" ]

  git rm subdir/missing.dat
  git add subdir
  git commit -m "add and remove files in subdirectory"

  expected="${oid:0:10} * subdir/some.dat"

  [ "$expected" = "$(git lfs ls-files)" ]

  diff -u <(git lfs ls-files --debug) <(cat <<-EOF
filepath: subdir/some.dat
    size: 9
checkout: true
download: true
     oid: sha256 $oid
 version: https://git-lfs.github.com/spec/v1

EOF)
)
end_test

begin_test "ls-files: run within subdirectory"
(
  set -e

  reponame="ls-files-in-subdir"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  mkdir subdir
  contents1="a"
  oid1="$(calc_oid "$contents1")"
  printf "%s" "$contents1" > a.dat
  contents2="b"
  oid2="$(calc_oid "$contents2")"
  printf "%s" "$contents2" > subdir/b.dat

  cd subdir

  [ "" = "$(git lfs ls-files)" ]

  git add ../a.dat b.dat

  expected="${oid1:0:10} * a.dat
${oid2:0:10} * subdir/b.dat"

  [ "$expected" = "$(git lfs ls-files)" ]

  diff -u <(git lfs ls-files --debug) <(cat <<-EOF
filepath: a.dat
    size: 1
checkout: true
download: true
     oid: sha256 $oid1
 version: https://git-lfs.github.com/spec/v1

filepath: subdir/b.dat
    size: 1
checkout: true
download: true
     oid: sha256 $oid2
 version: https://git-lfs.github.com/spec/v1

EOF)
)
end_test

begin_test "ls-files: checkout and download status"
(
  set -e

  reponame="ls-files-status"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  contents1="a"
  oid1="$(calc_oid "$contents1")"
  printf "%s" "$contents1" > a.dat
  contents2="b"
  oid2="$(calc_oid "$contents2")"
  printf "%s" "$contents2" > b.dat

  [ "" = "$(git lfs ls-files)" ]

  # Note that if we don't remove b.dat from the working tree as well as the
  # Git LFS object cache, Git calls (as invoked by Git LFS) may restore the
  # cache copy from the working tree copy by re-invoking Git LFS in
  # "clean" filter mode.
  git add a.dat b.dat
  rm a.dat b.dat
  rm ".git/lfs/objects/${oid2:0:2}/${oid2:2:2}/$oid2"

  expected="${oid1:0:10} - a.dat
${oid2:0:10} - b.dat"

  [ "$expected" = "$(git lfs ls-files)" ]

  diff -u <(git lfs ls-files --debug) <(cat <<-EOF
filepath: a.dat
    size: 1
checkout: false
download: true
     oid: sha256 $oid1
 version: https://git-lfs.github.com/spec/v1

filepath: b.dat
    size: 1
checkout: false
download: false
     oid: sha256 $oid2
 version: https://git-lfs.github.com/spec/v1

EOF)
)
end_test

begin_test "ls-files: checkout and download status (run within subdirectory)"
(
  set -e

  reponame="ls-files-status-in-subdir"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  contents1="a"
  oid1="$(calc_oid "$contents1")"
  printf "%s" "$contents1" > a.dat
  contents2="b"
  oid2="$(calc_oid "$contents2")"
  printf "%s" "$contents2" > b.dat

  mkdir subdir
  cd subdir

  contents3="c"
  oid3="$(calc_oid "$contents3")"
  printf "%s" "$contents3" > c.dat
  contents4="d"
  oid4="$(calc_oid "$contents4")"
  printf "%s" "$contents4" > d.dat

  [ "" = "$(git lfs ls-files)" ]

  # Note that if we don't remove b.dat and d.dat from the working tree as
  # well as the Git LFS object cache, Git calls (as invoked by Git LFS) may
  # restore the cache copies from the working tree copies by re-invoking
  # Git LFS in "clean" filter mode.
  git add ../a.dat ../b.dat c.dat d.dat
  rm ../a.dat ../b.dat c.dat d.dat
  rm "../.git/lfs/objects/${oid2:0:2}/${oid2:2:2}/$oid2"
  rm "../.git/lfs/objects/${oid4:0:2}/${oid4:2:2}/$oid4"

  expected="${oid1:0:10} - a.dat
${oid2:0:10} - b.dat
${oid3:0:10} - subdir/c.dat
${oid4:0:10} - subdir/d.dat"

  [ "$expected" = "$(git lfs ls-files)" ]

  diff -u <(git lfs ls-files --debug) <(cat <<-EOF
filepath: a.dat
    size: 1
checkout: false
download: true
     oid: sha256 $oid1
 version: https://git-lfs.github.com/spec/v1

filepath: b.dat
    size: 1
checkout: false
download: false
     oid: sha256 $oid2
 version: https://git-lfs.github.com/spec/v1

filepath: subdir/c.dat
    size: 1
checkout: false
download: true
     oid: sha256 $oid3
 version: https://git-lfs.github.com/spec/v1

filepath: subdir/d.dat
    size: 1
checkout: false
download: false
     oid: sha256 $oid4
 version: https://git-lfs.github.com/spec/v1

EOF)
)
end_test

begin_test "ls-files: --size"
(
  set -e

  reponame="ls-files-size"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  contents="contents"
  size="$(printf "%s" "$contents" | wc -c | awk '{ print $1 }')"
  printf "%s" "$contents" > a.dat

  git add a.dat
  git commit -m "add a.dat"

  git lfs ls-files --size 2>&1 | tee ls.log
  [ "d1b2a59fbe * a.dat (8 B)" = "$(cat ls.log)" ]
)
end_test

begin_test "ls-files: indexed files without tree"
(
  set -e

  reponame="ls-files-indexed-files-without-tree"
  git init "$reponame"
  cd "$reponame"

  git lfs track '*.dat'
  git add .gitattributes

  contents="a"
  oid="$(calc_oid "$contents")"
  printf "%s" "$contents" > a.dat

  [ "" = "$(git lfs ls-files)" ]

  git add a.dat

  [ "${oid:0:10} * a.dat" = "$(git lfs ls-files)" ]
)
end_test

begin_test "ls-files: indexed file with tree"
(
  set -e

  reponame="ls-files-indexed-files-with-tree"
  git init "$reponame"
  cd "$reponame"

  git lfs track '*.dat'
  git add .gitattributes
  git commit -m "initial commit"

  tree_contents="a"
  tree_oid="$(calc_oid "$tree_contents")"

  printf "%s" "$tree_contents" > a.dat
  git add a.dat
  git commit -m "add a.dat"

  index_contents="b"
  index_oid="$(calc_oid "$index_contents")"

  printf "%s" "$index_contents" > a.dat
  git add a.dat

  [ "${index_oid:0:10} * a.dat" = "$(git lfs ls-files)" ]
)
end_test

begin_test "ls-files: historical reference ignores index"
(
  set -e

  reponame="ls-files-historical-reference-ignores-index"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.txt"
  echo "a.txt" > a.txt
  echo "b.txt" > b.txt
  echo "c.txt" > c.txt

  git add .gitattributes a.txt
  git commit -m "a.txt: initial commit"

  git add b.txt
  git commit -m "b.txt: initial commit"

  git add c.txt

  git lfs ls-files "$(git rev-parse HEAD~1)" 2>&1 | tee ls-files.log

  [ 1 -eq "$(grep -c "a.txt" ls-files.log)" ]
  [ 0 -eq "$(grep -c "b.txt" ls-files.log)" ]
  [ 0 -eq "$(grep -c "c.txt" ls-files.log)" ]
)
end_test

begin_test "ls-files: non-HEAD reference referring to HEAD ignores index"
(
  set -e

  reponame="ls-files-HEAD-ish-ignores-index"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.txt"
  echo "a.txt" > a.txt
  echo "b.txt" > b.txt

  git add .gitattributes a.txt
  git commit -m "a.txt: initial commit"

  tagname="v1.0.0"
  git tag "$tagname"

  git add b.txt

  git lfs ls-files "$tagname" 2>&1 | tee ls-files.log

  [ 1 -eq "$(grep -c "a.txt" ls-files.log)" ]
  [ 0 -eq "$(grep -c "b.txt" ls-files.log)" ]
)
end_test

begin_test "ls-files: outside git repository"
(
  set +e
  git lfs ls-files 2>&1 > ls-files.log
  res=$?

  set -e
  if [ "$res" = "0" ]; then
    echo "Passes because $GIT_LFS_TEST_DIR is unset."
    exit 0
  fi
  [ "$res" = "128" ]
  grep "Not in a Git repository" ls-files.log
)
end_test

begin_test "ls-files: --include"
(
  set -e

  git init ls-files-include
  cd ls-files-include

  git lfs track "*.dat" "*.bin"
  echo "a" > a.dat
  echo "b" > b.dat
  echo "c" > c.bin

  git add *.gitattributes a.dat b.dat c.bin
  git commit -m "initial commit"

  git lfs ls-files --include="*.dat" 2>&1 | tee ls-files.log

  [ "0" -eq "$(grep -c "\.bin" ls-files.log)" ]
  [ "2" -eq "$(grep -c "\.dat" ls-files.log)" ]
)
end_test

begin_test "ls-files: --exclude"
(
  set -e

  git init ls-files-exclude
  cd ls-files-exclude

  mkdir dir

  git lfs track "*.dat"
  echo "a" > a.dat
  echo "b" > b.dat
  echo "c" > dir/c.dat

  git add *.gitattributes a.dat b.dat dir/c.dat
  git commit -m "initial commit"

  git lfs ls-files --exclude="dir/" 2>&1 | tee ls-files.log

  [ "0" -eq "$(grep -c "dir" ls-files.log)" ]
  [ "2" -eq "$(grep -c "\.dat" ls-files.log)" ]
)
end_test

begin_test "ls-files: --include/--exclude with path cache settings"
(
  set -e

  git init ls-files-include-exclude
  cd ls-files-include-exclude

  mkdir -p dir

  git lfs track "*.dat"
  echo "a" > a.dat
  echo "b" > dir/b.dat
  echo "c" > dir/c.dat
  echo "d" > dir/d.dat

  git add *.gitattributes a.dat dir
  git commit -m "initial commit"

  git lfs ls-files --include="dir/" --exclude="c.dat" 2>&1 | tee ls-files.log

  [ 1 -eq $(grep -c "dir/b.dat" "ls-files.log") ]
  [ 1 -eq $(grep -c "dir/d.dat" "ls-files.log") ]
  [ 2 -eq $(cat "ls-files.log" | wc -l) ]

  # Also test with various path filter cache settings.
  for cache in "none" "0" "1" "unlimited" "" "-1" "invalid"; do
    git config "lfs.pathFilterCacheSize" "$cache"

    git lfs ls-files --include="dir/" --exclude="c.dat" 2>&1 | tee ls-files.log

    [ 1 -eq $(grep -c "dir/b.dat" "ls-files.log") ]
    [ 1 -eq $(grep -c "dir/d.dat" "ls-files.log") ]
    [ 2 -eq $(cat "ls-files.log" | wc -l) ]
  done
)
end_test

begin_test "ls-files: before first commit"
(
  set -e

  reponame="ls-files-before-first-commit"
  git init "$reponame"
  cd "$reponame"

  if [ 0 -ne $(git lfs ls-files | wc -l) ]; then
    echo >&2 "Expected \`git lfs ls-files\` to produce no output"
    exit 1
  fi
)
end_test

begin_test "ls-files: show duplicate files"
(
  set -e

  mkdir dupRepoShort
  cd dupRepoShort
  git init

  git lfs track "*.tgz" | grep "Tracking \"\*.tgz\""
  echo "test content" > one.tgz
  echo "test content" > two.tgz
  git add one.tgz
  git add two.tgz
  git commit -m "add duplicate files"

  expected="$(echo "a1fff0ffef * one.tgz
a1fff0ffef * two.tgz")"

  [ "$expected" = "$(git lfs ls-files)" ]
)
end_test

begin_test "ls-files: show duplicate files with long OID"
(
  set -e

  mkdir dupRepoLong
  cd dupRepoLong
  git init

  git lfs track "*.tgz" | grep "Tracking \"\*.tgz\""
  echo "test content" > one.tgz
  echo "test content" > two.tgz
  git add one.tgz
  git add two.tgz
  git commit -m "add duplicate files with long OID"

  expected="$(echo "a1fff0ffefb9eace7230c24e50731f0a91c62f9cefdfe77121c2f607125dffae * one.tgz
a1fff0ffefb9eace7230c24e50731f0a91c62f9cefdfe77121c2f607125dffae * two.tgz")"

  [ "$expected" = "$(git lfs ls-files --long)" ]
)
end_test

begin_test "ls-files: history with --all"
(
  set -e

  reponame="ls-files-history-with-all"
  git init "$reponame"
  cd "$reponame"

  git lfs track '*.dat'
  printf "a" > a.dat
  printf "b" > b.dat

  git add .gitattributes a.dat b.dat
  git commit -m "initial commit"

  rm b.dat
  git add b.dat
  git commit -m "remove b.dat"

  git lfs ls-files 2>&1 | tee ls-files.log
  [ 1 -eq $(grep -c "a\.dat" ls-files.log) ]
  [ 0 -eq $(grep -c "b\.dat" ls-files.log) ]

  git lfs ls-files --all 2>&1 | tee ls-files-all.log
  [ 1 -eq $(grep -c "a\.dat" ls-files-all.log) ]
  [ 1 -eq $(grep -c "b\.dat" ls-files-all.log) ]
)
end_test

begin_test "ls-files: --all with argument(s)"
(
  set -e

  reponame="ls-files-all-with-arguments"
  git init "$reponame"
  cd "$reponame"

  git lfs ls-files --all main 2>&1 | tee ls-files.log

  if [ "0" -eq "${PIPESTATUS[0]}" ]; then
    echo >&2 "fatal: \`git lfs ls-files --all main\` to fail"
    exit 1
  fi

  [ "Cannot use --all with explicit reference" = "$(cat ls-files.log)" ]
)
end_test

begin_test "ls-files: reference with --deleted"
(
  set -e

  reponame="ls-files-reference-with-deleted"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  printf "a" > a.dat
  git add .gitattributes a.dat
  git commit -m "initial commit"

  rm a.dat
  git add a.dat
  git commit -m "a.dat: remove a.dat"

  git lfs ls-files 2>&1 | tee ls-files.log
  git lfs ls-files --deleted 2>&1 | tee ls-files-deleted.log

  [ 0 -eq $(grep -c "a\.dat" ls-files.log) ]
  [ 1 -eq $(grep -c "a\.dat" ls-files-deleted.log) ]
)
end_test

begin_test "ls-files: invalid --all ordering"
(
  set -e

  reponame="ls-files-invalid---all-ordering"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  echo "Hello world" > a.dat

  git add .gitattributes a.dat
  git commit -m "initial commit"

  git lfs ls-files -- --all 2>&1 | tee ls-files.out
  if [ ${PIPESTATUS[0]} = "0" ]; then
    echo >&2 "Expected \`git lfs ls-files -- --all\' to fail"
    exit 1
  fi
  grep "Did you mean \`git lfs ls-files --all --\` ?" ls-files.out
)
end_test

begin_test "ls-files: list/stat files with escaped runes in path before commit"
(
  set -e

  reponame=runes-in-path
  content="zero"
  checksum="d3eb539a55"
  pathWithGermanRunes="german/äöü"
  fileWithGermanRunes="schüüch.bin"

  mkdir $reponame
  git init "$reponame"
  cd $reponame
  git lfs track "**/*"

  echo "$content" > regular
  echo "$content" > "$fileWithGermanRunes"

  mkdir -p "$pathWithGermanRunes"
  echo "$content" > "$pathWithGermanRunes/regular"
  echo "$content" > "$pathWithGermanRunes/$fileWithGermanRunes"

  git add *

  # check short form
  [ 4 -eq "$(git lfs ls-files | grep -c '*')" ]

  # also check long format
  [ 4 -eq "$(git lfs ls-files -l | grep -c '*')" ]

)
end_test

begin_test "ls-files: --name-only"
(
  set -e

  reponame="ls-files-name"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  contents="test contents"
  echo "$contents" > a.dat

  git add a.dat
  git commit -m "add a.dat"

  git lfs ls-files --name-only 2>&1 | tee ls.log
  [ "a.dat" = "$(cat ls.log)" ]
)
end_test

begin_test "ls-files: history with reference range"
(
  set -e

  reponame="ls-files-history-with-range"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m 'intial commit'

  echo "content of a-file" > a.dat
  git add a.dat
  git commit -m 'add a.dat'

  echo "content of b-file" > b.dat
  git add b.dat
  git commit -m 'add b.dat'

  git tag b-commit

  echo "content of c-file" > c.dat
  git add c.dat
  git commit -m 'add c.dat'

  echo "content of c-file and later modified" > c.dat
  git add c.dat
  git commit -m 'modify c.dat'

  git tag c-commit

  git rm a.dat
  git commit -m 'remove a.dat'

  git lfs ls-files --all 2>&1 | tee ls-files.log
  [ 1 -eq $(grep -c "a\.dat" ls-files.log) ]
  [ 1 -eq $(grep -c "b\.dat" ls-files.log) ]
  [ 2 -eq $(grep -c "c\.dat" ls-files.log) ]

  git lfs ls-files b-commit c-commit 2>&1 | tee ls-files.log
  [ 0 -eq $(grep -c "a\.dat" ls-files.log) ]
  [ 0 -eq $(grep -c "b\.dat" ls-files.log) ]
  [ 2 -eq $(grep -c "c\.dat" ls-files.log) ]

  git lfs ls-files c-commit~ c-commit 2>&1 | tee ls-files.log
  [ 0 -eq $(grep -c "a\.dat" ls-files.log) ]
  [ 0 -eq $(grep -c "b\.dat" ls-files.log) ]
  [ 1 -eq $(grep -c "c\.dat" ls-files.log) ]

  git lfs ls-files HEAD~ HEAD 2>&1 | tee ls-files.log
  [ 0 -eq $(grep -c "a\.dat" ls-files.log) ]
  [ 0 -eq $(grep -c "b\.dat" ls-files.log) ]
  [ 0 -eq $(grep -c "c\.dat" ls-files.log) ]
)
end_test

begin_test "ls-files: not affected by lfs.fetchexclude"
(
  set -e

  mkdir repo-fetchexclude
  cd repo-fetchexclude
  git init
  git lfs track "*.dat" | grep "Tracking \"\*.dat\""
  echo "some data" > some.dat
  echo "some text" > some.txt
  echo "missing" > missing.dat
  git add missing.dat
  git commit -m "add missing file"
  git config lfs.fetchexclude '*'
  [ "6bbd052ab0 * missing.dat" = "$(git lfs ls-files)" ]
)
end_test

begin_test "ls-files --json"
(
  set -e

  reponame="ls-files-json"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat" | grep "Tracking \"\*.dat\""
  echo "some data" > some.dat
  echo "some text" > some.txt
  echo "missing" > missing.dat
  git add missing.dat
  git commit -m "add missing file"

  git lfs ls-files --json > actual
  cat > expected <<-EOF
{
 "files": [
  {
   "name": "missing.dat",
   "size": 8,
   "checkout": true,
   "downloaded": true,
   "oid_type": "sha256",
   "oid": "6bbd052ab054ef222c1c87be60cd191addedd24cc882d1f5f7f7be61dc61bb3a",
   "version": "https://git-lfs.github.com/spec/v1"
  }
 ]
}
EOF
  diff -u actual expected

  git rm missing.dat
  git add some.dat some.txt
  git commit -m "added some files, removed missing one"

  git lfs ls-files --json > actual
  cat > expected <<-EOF
{
 "files": [
  {
   "name": "some.dat",
   "size": 10,
   "checkout": true,
   "downloaded": true,
   "oid_type": "sha256",
   "oid": "5aa03f96c77536579166fba147929626cc3a97960e994057a9d80271a736d10f",
   "version": "https://git-lfs.github.com/spec/v1"
  }
 ]
}
EOF
  diff -u actual expected
)
end_test

begin_test "ls-files: files in subdirectory (--json)"
(
  set -e

  reponame="ls-files-subdir-json"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  mkdir subdir
  missing="missing"
  missing_oid="$(calc_oid "$missing")"
  printf "%s" "$missing" > subdir/missing.dat
  git add subdir
  git commit -m "add file in subdirectory"

  contents="some data"
  oid="$(calc_oid "$contents")"
  printf "%s" "$contents" > subdir/some.dat

  echo "some text" > subdir/some.txt

  git rm subdir/missing.dat
  git add subdir
  git commit -m "add and remove files in subdirectory"

  diff -u <(git lfs ls-files --json) <(cat <<-EOF
{
 "files": [
  {
   "name": "subdir/some.dat",
   "size": 9,
   "checkout": true,
   "downloaded": true,
   "oid_type": "sha256",
   "oid": "$oid",
   "version": "https://git-lfs.github.com/spec/v1"
  }
 ]
}
EOF)
)
end_test

begin_test "ls-files: run within subdirectory (--json)"
(
  set -e

  reponame="ls-files-in-subdir-json"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  mkdir subdir
  contents1="a"
  oid1="$(calc_oid "$contents1")"
  printf "%s" "$contents1" > a.dat
  contents2="b"
  oid2="$(calc_oid "$contents2")"
  printf "%s" "$contents2" > subdir/b.dat

  cd subdir

  git add ../a.dat b.dat

  diff -u <(git lfs ls-files --json) <(cat <<-EOF
{
 "files": [
  {
   "name": "a.dat",
   "size": 1,
   "checkout": true,
   "downloaded": true,
   "oid_type": "sha256",
   "oid": "$oid1",
   "version": "https://git-lfs.github.com/spec/v1"
  },
  {
   "name": "subdir/b.dat",
   "size": 1,
   "checkout": true,
   "downloaded": true,
   "oid_type": "sha256",
   "oid": "$oid2",
   "version": "https://git-lfs.github.com/spec/v1"
  }
 ]
}
EOF)
)
end_test

begin_test "ls-files: checkout and download status (--json)"
(
  set -e

  reponame="ls-files-status-json"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  contents1="a"
  oid1="$(calc_oid "$contents1")"
  printf "%s" "$contents1" > a.dat
  contents2="b"
  oid2="$(calc_oid "$contents2")"
  printf "%s" "$contents2" > b.dat

  # Note that if we don't remove b.dat from the working tree as well as the
  # Git LFS object cache, Git calls (as invoked by Git LFS) may restore the
  # cache copy from the working tree copy by re-invoking Git LFS in
  # "clean" filter mode.
  git add a.dat b.dat
  rm a.dat b.dat
  rm ".git/lfs/objects/${oid2:0:2}/${oid2:2:2}/$oid2"

  diff -u <(git lfs ls-files --json) <(cat <<-EOF
{
 "files": [
  {
   "name": "a.dat",
   "size": 1,
   "checkout": false,
   "downloaded": true,
   "oid_type": "sha256",
   "oid": "$oid1",
   "version": "https://git-lfs.github.com/spec/v1"
  },
  {
   "name": "b.dat",
   "size": 1,
   "checkout": false,
   "downloaded": false,
   "oid_type": "sha256",
   "oid": "$oid2",
   "version": "https://git-lfs.github.com/spec/v1"
  }
 ]
}
EOF)
)
end_test

begin_test "ls-files: checkout and download status (run within subdirectory) (--json)"
(
  set -e

  reponame="ls-files-status-in-subdir-json"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  contents1="a"
  oid1="$(calc_oid "$contents1")"
  printf "%s" "$contents1" > a.dat
  contents2="b"
  oid2="$(calc_oid "$contents2")"
  printf "%s" "$contents2" > b.dat

  mkdir subdir
  cd subdir

  contents3="c"
  oid3="$(calc_oid "$contents3")"
  printf "%s" "$contents3" > c.dat
  contents4="d"
  oid4="$(calc_oid "$contents4")"
  printf "%s" "$contents4" > d.dat

  # Note that if we don't remove b.dat and d.dat from the working tree as
  # well as the Git LFS object cache, Git calls (as invoked by Git LFS) may
  # restore the cache copies from the working tree copies by re-invoking
  # Git LFS in "clean" filter mode.
  git add ../a.dat ../b.dat c.dat d.dat
  rm ../a.dat ../b.dat c.dat d.dat
  rm "../.git/lfs/objects/${oid2:0:2}/${oid2:2:2}/$oid2"
  rm "../.git/lfs/objects/${oid4:0:2}/${oid4:2:2}/$oid4"

  diff -u <(git lfs ls-files --json) <(cat <<-EOF
{
 "files": [
  {
   "name": "a.dat",
   "size": 1,
   "checkout": false,
   "downloaded": true,
   "oid_type": "sha256",
   "oid": "$oid1",
   "version": "https://git-lfs.github.com/spec/v1"
  },
  {
   "name": "b.dat",
   "size": 1,
   "checkout": false,
   "downloaded": false,
   "oid_type": "sha256",
   "oid": "$oid2",
   "version": "https://git-lfs.github.com/spec/v1"
  },
  {
   "name": "subdir/c.dat",
   "size": 1,
   "checkout": false,
   "downloaded": true,
   "oid_type": "sha256",
   "oid": "$oid3",
   "version": "https://git-lfs.github.com/spec/v1"
  },
  {
   "name": "subdir/d.dat",
   "size": 1,
   "checkout": false,
   "downloaded": false,
   "oid_type": "sha256",
   "oid": "$oid4",
   "version": "https://git-lfs.github.com/spec/v1"
  }
 ]
}
EOF)
)
end_test
