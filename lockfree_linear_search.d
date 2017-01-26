import core.atomic;
import std.stdio;

struct Entry {
	size_t key;
	size_t value;
}

struct Store(size_t MAX_ENTRIES) {
	shared Entry[MAX_ENTRIES] m_entries;
	// returns true if there was space for the value
	bool setEntry(size_t key, size_t value) {
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
}

enum SIZE = 102;

__gshared Store!SIZE store;

void main() {
	auto sw = StopWatch.create();
	import std.parallelism : taskPool, task;
	auto input = new size_t[SIZE];
	foreach (ref i; 0 .. input.length) {
		input[i] = i;
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
		unique_stacks[item.value] ~= item.key;
		count++;
	}
	writeln("blame stacks:");
	foreach (old_n_ptr_addr, stack; unique_stacks) {
		writeln(old_n_ptr_addr, ": ", stack);
	}
	writeln("count: ", count);
	sw.print();
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
			writeln(t);
		}
	}
}