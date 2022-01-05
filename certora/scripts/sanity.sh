
make -C certora munged

certoraRun \
    certora/harness/StableJoeStakingHarness.sol \
    certora/helpers/DummyERC20A.sol \
    certora/helpers/DummyERC20B.sol \
    --verify StableJoeStakingHarness:certora/spec/sanity.spec \
    --rule sanity                       \
    --solc solc6.12                     \
    --solc_args '["--optimize"]' \
    --settings -t=60 \
    --msg "sanity StableJoeStaking" \
    --send_only \
    --staging \
    $*
