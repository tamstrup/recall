#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/fixtures
say -v Samantha -r 155 -o .build/fixtures/one.aiff 'Let us keep the first version small. We have decided to release it on Friday. I will write the release notes tomorrow. We should keep the recordings on this Mac.'
say -v Daniel -r 150 -o .build/fixtures/two.aiff 'That sounds good. I will test audio import on Thursday and check that we can rename speakers. Please include the meeting minutes in our Friday review.'
say -v Sara -r 145 -o .build/fixtures/danish.aiff 'Hej, jeg hedder Patrick, og det her er en dansk optagelse med kun én person. I morgen skal jeg til møde i København. Vi skal tale om den nye version af vores program. Jeg vil gerne have et dansk referat af samtalen. Alle optagelser bliver på min computer. På fredag tester jeg, om teksten bliver skrevet på det rigtige sprog, og om programmet kan genkende, at det er den samme person, der taler hele tiden.'
afconvert .build/fixtures/danish.aiff .build/fixtures/danish.wav -f WAVE -d LEI16@16000 -c 1
afconvert .build/fixtures/one.aiff .build/fixtures/one.wav -f WAVE -d LEI16@16000 -c 1
afconvert .build/fixtures/two.aiff .build/fixtures/two.wav -f WAVE -d LEI16@16000 -c 1
python3 - <<'PY'
import wave, array
with wave.open('.build/fixtures/meeting.wav', 'wb') as output:
    output.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
    for name in ['one', 'two', 'one', 'two']:
        with wave.open('.build/fixtures/' + name + '.wav', 'rb') as part:
            data = part.readframes(part.getnframes())
            assert len(data) > 16000 and max(map(abs, array.array('h', data))) > 100, 'Synthetic speech is empty; check voice access.'
            output.writeframes(data)
        output.writeframes(b'\0' * 16000)
PY
afconvert .build/fixtures/meeting.wav .build/fixtures/meeting.m4a -f m4af -d aac
# Public silent MP3 fixture, used only to exercise AVFoundation's MP3 decoder.
if [[ ! -f .build/fixtures/silence.mp3 ]]; then
    curl -L --fail https://raw.githubusercontent.com/anars/blank-audio/master/1-second-of-silence.mp3 -o .build/fixtures/silence.mp3
fi
RECALL_TEST_AUDIO="$PWD/.build/fixtures/meeting.wav" \
RECALL_TEST_DANISH_AUDIO="$PWD/.build/fixtures/danish.wav" \
RECALL_TEST_MODELS="$PWD/.build/test-models" \
RECALL_TEST_SUMMARY=1 \
Scripts/swift.sh test --enable-swift-testing --filter LocalModelIntegrationTests
