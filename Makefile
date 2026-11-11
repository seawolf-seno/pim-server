.PHONY: test test-seed test-lua dev-up dev-down

test: test-seed test-lua

test-seed:
	python3 -I -m unittest discover -s tests -p 'test_*.py'

test-lua:
	lua5.4 tests/test_schedule.lua
	lua5.4 tests/test_rooms.lua

dev-up:
	bin/pim-dev up

dev-down:
	bin/pim-dev down
