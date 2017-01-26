module lockfree_linear_search;

import core.atomic;
import std.stdio;
import std.exception;

shared
struct Store(size_t MAX_ENTRIES) {
	private struct Entry {
		size_t key;
		size_t value;
	}
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
