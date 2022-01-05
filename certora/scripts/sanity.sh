
make -C certora munged

for i in `ls certora/harness`
do
    certoraRun certora/harness/$i \
        --verify $(basename $i .sol):certora/spec/sanity.spec \
        --rule sanity                       \
        --solc solc6.12                     \
        --solc_args '["--optimize"]' \
        --settings -t=60 \
        --msg "sanity $i" \
        --send_only \
        --staging \
        $*
done
