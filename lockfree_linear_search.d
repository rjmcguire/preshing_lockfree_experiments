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

__gshared Store!100 store;

import core.thread;
void worker() {
	new Thread({
		import std.random;
		size_t k;
		foreach (i; 0..99) {
			k = uniform(100, 999);
			if (!store.setEntry(k,22)) {
				writeln("out of space @ ", i);
				break;
			}
		}
	}).start();
}

void main() {
	auto sw = StopWatch.create();
	worker();
	worker();
	worker();
	sw.next();
	writeln("waiting");
	thread_joinAll();
	sw.next();
	writeln(store);
	sw.print();
}



struct StopWatch {
	import std.datetime : StopWatch;
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