#!/home/users/pjh/bin/python
import itertools

l = list()
while True:
    l.extend(itertools.repeat('aaaaaaaaaaaaaaaaaaaaaaaaa', int(1e6)))

