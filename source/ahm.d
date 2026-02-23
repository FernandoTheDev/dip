module ahm;

import core.stdc.stdlib : malloc, realloc, free;
import core.stdc.string : memcpy, memset;
import vm : HVMValue;

struct ArrayHashMap
{
    private struct Bucket
    {
        long key;
        HVMValue value;
    }

    Bucket* data;
    int* hashIdx;
    size_t capacity;
    private size_t length;
    private long nextAutoIndex;

    private enum float LOAD_FACTOR = 0.75;
    private enum int EMPTY = -1;

    void initialize(size_t initialCapacity = 8) @nogc nothrow
    {
        capacity = initialCapacity;
        length = 0;
        nextAutoIndex = 0;

        data = cast(Bucket*) malloc(Bucket.sizeof * capacity);        
        hashIdx = cast(int*) malloc(int.sizeof * capacity);
        for(size_t i = 0; i < capacity; i++) hashIdx[i] = EMPTY;
    }

    ~this() @nogc nothrow
    {
        if (data) free(data);
        if (hashIdx) free(hashIdx);
    }

    private size_t hashFunc(long key) const @nogc nothrow
    {
        return cast(size_t)(key ^ (key >>> 32));
    }

    void put(long key, HVMValue value) @nogc nothrow
    {
        if (cast(float)(length + 1) / capacity > LOAD_FACTOR)
            resize();

        if (key >= nextAutoIndex) nextAutoIndex = key + 1;

        size_t h = hashFunc(key) % capacity;
        while (hashIdx[h] != EMPTY)
        {
            if (data[hashIdx[h]].key == key)
            {
                data[hashIdx[h]].value = value;
                return;
            }
            h = (h + 1) % capacity;
        }

        uint currentIdx = cast(uint)length;
        data[currentIdx].key = key;
        data[currentIdx].value = value;
        hashIdx[h] = cast(int)currentIdx;
        length++;
    }

    void append(HVMValue value) @nogc nothrow
    {
        put(nextAutoIndex, value);
    }

    HVMValue* get(long key) @nogc nothrow
    {
        if (capacity == 0) return null;
        size_t h = hashFunc(key) % capacity;
        
        while (hashIdx[h] != EMPTY)
        {
            int dataPos = hashIdx[h];
            if (data[dataPos].key == key)
                return &data[dataPos].value;
            h = (h + 1) % capacity;
        }
        return null;
    }

    private void resize() @nogc nothrow
    {
        size_t oldCapacity = capacity;
        Bucket* oldData = data;
        
        capacity *= 2;
        data = cast(Bucket*) malloc(Bucket.sizeof * capacity);
        hashIdx = cast(int*) realloc(hashIdx, int.sizeof * capacity);
        
        for(size_t i = 0; i < capacity; i++) hashIdx[i] = EMPTY;
        
        memcpy(data, oldData, Bucket.sizeof * length);
        for (int i = 0; i < cast(int)length; i++)
        {
            size_t h = hashFunc(data[i].key) % capacity;
            while (hashIdx[h] != EMPTY) h = (h + 1) % capacity;
            hashIdx[h] = i;
        }
        free(oldData);
    }

    size_t size() const @nogc nothrow { return length; }
}
