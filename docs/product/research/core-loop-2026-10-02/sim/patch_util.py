import sys
def patch(path, pairs, extra_sub=None):
    s = open(path, encoding='utf-8').read()
    miss = []
    for i, (a, b) in enumerate(pairs):
        if a not in s:
            miss.append((i, a[:70])); continue
        if s.count(a) > 1:
            miss.append((i, 'DUP:' + a[:60])); continue
        s = s.replace(a, b)
    if extra_sub:
        for a, b in extra_sub:
            s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)
    print(f'{path}: {len(pairs)-len(miss)}/{len(pairs)} applied')
    for m in miss:
        print('  MISS', m)
    return miss
