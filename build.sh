#!/bin/bash -e
source ./build_info.sh
[[ $RUBY ]] || { echo 'please set $RUBY' && exit 1; }
echo "EVERYBODY STAND BACK, WE'RE INSTALLING $RUBY"
if [ `expr $RUBY : '.*-clang$'` -gt 0 ]; then
  CC=${RUBY##*-}
fi

source ~/.bashrc
unset DYLD_LIBRARY_PATH

travis_retry() {
  local result=0
  local count=1
  while [ $count -le 3 ]; do
    [ $result -ne 0 ] && {
      echo -e "\n\033[33;1mThe command \"$@\" failed. Retrying, $count of 3.\033[0m\n" >&2
    }
    "$@"
    result=$?
    [ $result -eq 0 ] && break
    count=$(($count + 1))
    sleep 1
  done

  [ $count -eq 3 ] && {
    echo "\n\033[33;1mThe command \"$@\" failed 3 times.\033[0m\n" >&2
  }

  return $result
}

fold_start() {
  echo -e "travis_fold:start:$1\033[33;1m$2\033[0m"
}

fold_end() {
  echo -e "\ntravis_fold:end:$1\r"
}

#######################################################
# update rvm
fold_start rvm.1 "update rvm"
rvm remove 1.8.7
rvm get stable
rvm reload
rvm cleanup all
fold_end rvm.1

#######################################################
# get rid of binary meta data
fold_start rvm.2 "clean up meta data"
echo -n > $rvm_path/user/md5
echo -n > $rvm_path/user/sha512
echo -n > $rvm_path/user/db || true
fold_end rvm.2

#######################################################
# build the binary
fold_start build "build $RUBY"
rvm alias delete $RUBY
rvm remove $RUBY
rvm install $RUBY --verify-downloads 1
rvm prepare $RUBY
fold_end build

#######################################################
# make sure bundler works
fold_start check.1 "make sure bundler works"
echo "source 'https://rubygems.org'; gem 'rails'" > Gemfile
travis_retry rvm $RUBY do gem install bundler
travis_retry rvm $RUBY do bundle install
fold_end check.1

#######################################################
# publish to bucket
fold_start publish "upload to S3"
gem install faraday -v 0.8.9
gem install travis-artifacts
travis-artifacts upload --path $RUBY.* --target-path binary
fold_end publish

#######################################################
# make sure it installs
fold_start check.2 "make sure it installs"
rvm remove $RUBY
echo "rvm_remote_server_url3=https://s3.amazonaws.com/travis-rubies
rvm_remote_server_path3=binary
rvm_remote_server_verify_downloads3=1" > $rvm_path/user/db
rvm install $RUBY --binary
fold_end check.2

