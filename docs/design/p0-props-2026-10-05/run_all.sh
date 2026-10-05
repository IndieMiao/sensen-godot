#!/bin/bash
cd "$(dirname "$0")"
job(){ n=$1; case $n in
  kitchen-room-*) refs="refs/ingame-farm.png refs/style-ref3.jpg refs/cook1-kitchen.png";;
  tackle-room-*) refs="refs/ingame-farm.png refs/style-ref3.jpg refs/npc1b-tackle.png";;
  *) refs="refs/ingame-farm.png refs/kit-lineup.png";;
 esac
 bash gen_scene.sh "$n" "$n.prompt.txt" $refs > /dev/null 2>&1; tail -1 "$n.log"; }
export -f job
ls *.prompt.txt | sed 's/.prompt.txt//' | xargs -P 3 -I{} bash -c 'job {}'
echo ALL_DONE
