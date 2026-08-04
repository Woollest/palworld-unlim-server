#!/bin/sh
set -eu

# The official image runs the server as a non-root user.
sudo chown -R user:usergroup /pal/Package/Pal/Saved
exec /bin/sh /pal/Package/PalServer.sh "$@"
