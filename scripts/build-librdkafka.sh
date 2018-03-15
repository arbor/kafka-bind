#!/bin/bash

RDKAFKA_VER="24e4fae8c54c4d7f5ab5326a1b6fa2f8d163682f"

PRJ=$PWD
DST="$PRJ/.librdkafka"
VERSION_FILE="$DST/version.txt"

if [ -f $VERSION_FILE ]; then
    echo "Found librdkafka: $(cat $VERSION_FILE), expected: $RDKAFKA_VER"
else
    echo "librdkafka not found in $DST"
fi

if [ -f $VERSION_FILE ] && [ "$(cat $VERSION_FILE)" == $RDKAFKA_VER ]; then
    echo "Required version found, using it"
    sudo cp -r $DST/* /usr/
    exit 0
fi

echo "Making librdkafka ($RDKAFKA_VER)"
SRC=`mktemp -d 2>/dev/null || mktemp -d -t 'rdkafka'`
git clone https://github.com/edenhill/librdkafka "$SRC"
cd $SRC
git reset $RDKAFKA_VER --hard

./configure --prefix $DST
cd src
make && make install
find $DST/lib -type f -executable | xargs strip
sudo cp -r $DST/* /usr/

echo "Writing version file to $VERSION_FILE"
echo $RDKAFKA_VER > $VERSION_FILE
