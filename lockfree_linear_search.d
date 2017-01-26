import core.atomic;
import std.stdio;
import std.exception;

struct Entry {
	size_t key;
	size_t value;
}

shared
struct Store(size_t MAX_ENTRIES) {
	Entry[MAX_ENTRIES] m_entries;
	// returns true if there was space for the value
	bool setEntry(size_t key, size_t value) {
		enforce(key != 0, "empty keys are not allowed");
		foreach (ref entry; m_entries) {
			//auto probedKey = atomicLoad!(MemoryOrder.acq)(entry.key); // correct optimised memory order?
			auto probedKey = atomicLoad(entry.key);
			if (probedKey != key) {
				if (probedKey != 0) {
					// not our key
					continue;
				}

				if (!cas(&entry.key, probedKey, key)) {
					// some other process stole our slot
					continue;
				}
			}
			atomicStore(entry.value, value);
			return true;
		}
		return false;
	}
	size_t getEntry(size_t key) {
		enforce(key != 0, "empty keys are not allowed");
		foreach (ref entry; m_entries) {
			//auto probedKey = atomicLoad!(MemoryOrder.acq)(entry.key); // correct optimised memory order?
			auto probedKey = atomicLoad(entry.key);
			if (probedKey == key) {
				return entry.value;
			}
		}
		return size_t.init;
	}
}

enum SIZE = 1024;

shared Store!SIZE store;

void main() {
	auto sw = StopWatch.create();
	import std.parallelism : taskPool, task;
	auto input = new size_t[SIZE];
	foreach (ref i; 0 .. input.length) {
		input[i] = i+1;
	}
	sw.next();
	writeln("doing parallel inserts");
	foreach (i, k; taskPool.parallel(input, 20)) {
		static size_t n;
		if (!store.setEntry(k, cast(ulong)&n)) {
			writeln("out of space @", i);
			throw new Exception("not enough space in storage");
		}
	}
	sw.next();
	writeln("back in main");

	size_t count;
	size_t[][size_t] unique_stacks;
	foreach (item; store.m_entries) {
		unique_stacks[store.getEntry(item.key)] ~= item.key;
		count++;
	}
	writeln("blame stacks:");
	foreach (old_n_ptr_addr, stack; unique_stacks) {
		writeln(old_n_ptr_addr, ": ", stack);
	}
	writeln("count: ", count);
	sw.print();
}

// test that values exactly match keys
unittest {
	writeln("test1");
	shared Store!(2048) store;
	import std.parallelism : taskPool, task;
	auto input = new size_t[2048];
	foreach (i; 0 .. input.length) {
		input[i] = i+1;
	}
	foreach (i, k; taskPool.parallel(input, 20)) {
		if (!store.setEntry(k, k)) {
			writeln("out of space @", i);
			throw new Exception("not enough space in storage");
		}
	}


	foreach (i, k; store.m_entries) {
		assert(store.getEntry(k.key)==k.value);
	}
	writeln("test1: okay");
}
// test that values stay set according to who set them
unittest {
	writeln("test2");
	shared Store!(2048) store;
	import std.parallelism : taskPool, task;
	auto input = new size_t[2][2048];
	// setup values
	foreach (i; 0 .. 2048) {
		input[i][0] = i+1;
	}
	// TODO: set values to a unique value per set of 20
	foreach (i, ref k; taskPool.parallel(input, 20)) {
		import std.random;
		size_t n = uniform(0, size_t.max);
		k[1] = n;
	}
	foreach (i, k; taskPool.parallel(input, 20)) {
		if (!store.setEntry(k[0], k[1])) {
			writeln("out of space @", i);
			throw new Exception("not enough space in storage");
		}
	}
	foreach (item; input) {
		assert(store.getEntry(item[0]) == item[1]);
	}
	writeln("test2: okay");
}

struct StopWatch {
	import std.datetime : StopWatch, TickDuration;
	StopWatch sw;
	TickDuration[] times;
	@disable this();
	static auto create() {
		typeof(this) ret = this.init;
		ret.sw.start();
		ret.times ~= ret.sw.peek();
		return ret;
	}
	void next() {
		times ~= sw.peek() - times[$-1];
	}
	void print() {
		foreach (t; times) {
			writeln(t.usecs, "us");
		}
	}
}