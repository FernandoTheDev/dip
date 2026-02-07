module hm;

import core.stdc.stdlib : malloc, realloc, free;
import core.stdc.string : memcpy, memset;

struct HashMap(K, V)
{
    private struct Entry
    {
        K key;
        V value;
        bool occupied;
        bool deleted;
    }

    private Entry* buckets;
    private size_t capacity;
    private size_t length;
    private enum float LOAD_FACTOR = 0.75;

    @disable this(this); // Previne cópias acidentais

    void initialize(size_t initialCapacity = 16) @nogc nothrow
    {
        capacity = initialCapacity;
        length = 0;
        buckets = cast(Entry*) malloc(Entry.sizeof * capacity);
        memset(buckets, 0, Entry.sizeof * capacity);
    }

    ~this() @nogc nothrow
    {
        if (buckets !is null)
        {
            free(buckets);
            buckets = null;
        }
    }

    private size_t hash(K key) const @nogc nothrow
    {
        static if (is(K == string))
        {
            size_t h = 5381;
            foreach (c; key)
                h = ((h << 5) + h) + c;
            return h;
        }
        else
            return cast(size_t) key;
    }

    private size_t findSlot(K key, out bool found) @nogc nothrow
    {
        size_t index = hash(key) % capacity;
        size_t firstDeleted = size_t.max;

        for (size_t i = 0; i < capacity; i++)
        {
            size_t probe = (index + i) % capacity;

            if (!buckets[probe].occupied)
            {
                if (!buckets[probe].deleted)
                {
                    found = false;
                    return firstDeleted != size_t.max ? firstDeleted : probe;
                }
                else if (firstDeleted == size_t.max)
                    firstDeleted = probe;
            }
            else if (buckets[probe].key == key)
            {
                found = true;
                return probe;
            }
        }

        found = false;
        return firstDeleted;
    }

    // Redimensiona a tabela
    private void resize() @nogc nothrow
    {
        size_t oldCapacity = capacity;
        Entry* oldBuckets = buckets;

        capacity *= 2;
        buckets = cast(Entry*) malloc(Entry.sizeof * capacity);
        memset(buckets, 0, Entry.sizeof * capacity);
        length = 0;

        // Reinsere elementos
        for (size_t i = 0; i < oldCapacity; i++)
            if (oldBuckets[i].occupied && !oldBuckets[i].deleted)
                put(oldBuckets[i].key, oldBuckets[i].value);

        free(oldBuckets);
    }

    void put(K key, V value) @nogc nothrow
    {
        if (cast(float)(length + 1) / capacity > LOAD_FACTOR)
            resize();

        bool found;
        size_t index = findSlot(key, found);

        if (!found && buckets[index].occupied)
            return; // Tabela cheia (não deveria acontecer)

        if (!buckets[index].occupied || buckets[index].deleted)
            length++;

        buckets[index].key = key;
        buckets[index].value = value;
        buckets[index].occupied = true;
        buckets[index].deleted = false;
    }

    V* get(K key) @nogc nothrow
    {
        bool found;
        size_t index = findSlot(key, found);
        if (found && !buckets[index].deleted)
            return &buckets[index].value;
        return null;
    }

    bool remove(K key) @nogc nothrow
    {
        bool found;
        size_t index = findSlot(key, found);

        if (found && !buckets[index].deleted)
        {
            buckets[index].deleted = true;
            length--;
            return true;
        }

        return false;
    }

    bool contains(K key) @nogc nothrow
    {
        return get(key) !is null;
    }

    size_t size() const @nogc nothrow
    {
        return length;
    }

    void clear() @nogc nothrow
    {
        memset(buckets, 0, Entry.sizeof * capacity);
        length = 0;
    }
}
