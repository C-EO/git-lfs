SHELL = bash
RM ?= rm -f
PROVE ?= prove
PROVE_EXTRA_ARGS =
DEFAULT_TEST_TARGET ?= test

GO ?= go

# GOTOOLCHAIN is an environment variable which, when set to 'local',
# prevents Go from downloading and running non-local versions of itself.
export GOTOOLCHAIN = local

ifeq ($(OS),Windows_NT)
X ?= .exe
else
X ?=
endif

TEST_CMDS =

TEST_CMDS += ../bin/git-credential-lfsnoop$X
TEST_CMDS += ../bin/git-credential-lfstest$X
TEST_CMDS += ../bin/lfs-askpass$X
TEST_CMDS += ../bin/lfs-ssh-echo$X
TEST_CMDS += ../bin/lfs-ssh-proxy-test$X
TEST_CMDS += ../bin/lfstest-badpathcheck$X
TEST_CMDS += ../bin/lfstest-count-tests$X
TEST_CMDS += ../bin/lfstest-customadapter$X
TEST_CMDS += ../bin/lfstest-genrandom$X
TEST_CMDS += ../bin/lfstest-gitserver$X
TEST_CMDS += ../bin/lfstest-nanomtime$X
TEST_CMDS += ../bin/lfstest-realpath$X
TEST_CMDS += ../bin/lfstest-standalonecustomadapter$X
TEST_CMDS += ../bin/lfstest-testutils$X

# Not used for the integration tests, but build it here anyway to ensure it
# continues to work.
TEST_CMDS += ../bin/git-lfs-test-server-api$X

TEST_SRCS     = $(wildcard t-*.sh)
TEST_API_SRCS = $(wildcard git-lfs-test-server-api/*.go)

all : $(DEFAULT_TEST_TARGET)

test-commands : $(TEST_CMDS)

test : test-commands
	$(RM) -r remote test_count{,.lock}
	@. ./testenv.sh && setup && cd t && \
		RM_GIT_LFS_TEST_DIR=no $(PROVE) $(PROVE_EXTRA_ARGS) t-*.sh && \
		shutdown

.PHONY : $(TEST_SRCS)
$(TEST_SRCS) : $(TEST_CMDS)
	$(RM) -r remote test_count{,.lock}
	$(PROVE) -v $(PROVE_EXTRA_ARGS) $@

.PHONY : clean
clean :
	$(RM) -r remote
	$(RM) $(TEST_CMDS)

../bin/%$X : cmd/%.go
	$(GO) build -o $@ $^

../bin/git-lfs-test-server-api$X : $(TEST_API_SRCS)
	$(GO) build -o $@ $^
