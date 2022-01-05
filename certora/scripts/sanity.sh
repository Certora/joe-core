
make -C certora munged

certoraRun \
    certora/harness/JoeBarV2Harness.sol \
    certora/harness/BarRewarderPerSecHarness.sol \
    certora/harness/JoeTokenHarness.sol \
    --link JoeBarV2Harness:joe=JoeTokenHarness \
           BarRewarderPerSecHarness:joe=JoeTokenHarness \
           BarRewarderPerSecHarness:bar=JoeBarV2Harness \
           JoeBarV2Harness:rewarder=BarRewarderPerSecHarness \
    --verify JoeBarV2Harness:certora/spec/sanity.spec \
             BarRewarderPerSecHarness:certora/spec/sanity.spec \
             JoeTokenHarness:certora/spec/sanity.spec \
    --rule sanity                       \
    --solc solc6.12                     \
    --solc_args '["--optimize"]' \
    --settings -t=60 \
    --msg "sanity $i" \
    --send_only \
    --staging \
    $*
