
make -C certora munged

echo "TODO: fix the sanity script"
exit 1

certoraRun \
    certora/harness/ExampleHarness.sol \
    certora/helpers/DummyERC20A.sol    \
    certora/helpers/DummyERC20B.sol    \
    --verify ExampleHarness:certora/spec/sanity.spec \
    --rule sanity                       \
    --solc solc8.0                      \
    --solc_args '["--optimize"]' \
    --settings -t=60, \
    --msg "sanity $1" \
    --staging \
    $*


