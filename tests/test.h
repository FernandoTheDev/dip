#ifndef VM_H
#define VM_H

#include <stdint.h>
#include <stdbool.h>

// Enums
typedef enum {
    HVMType_Bool,
    HVMType_Char,
    HVMType_Int,
    HVMType_Float,
    HVMType_String,
    HVMType_Array,
} HVMType;

// Structs
typedef struct {
    char* value;
    uint32_t length;
} HVMString;

typedef struct {} HVMArray;

typedef union {
    int64_t i32;
    int8_t i8;
    bool i1;
    double f32;
    HVMString str;
    HVMArray ht;
} HVMLiteral;

typedef struct {
    HVMType type;
    HVMLiteral value;
} HVMValue;

typedef struct HVM HVM;

// Funções da VM
extern HVM* HVM_create(uint32_t* program, uint32_t programSize, 
                       HVMValue* constantPool, uint32_t constantPoolSize, 
                       bool clean);
extern void HVM_run(HVM* self);
extern void HVM_clear(HVM* self);
extern void HVM_push(HVM* self, HVMValue value);

// Funções de HVMValue
extern HVMValue HVMValue_makeInt(int64_t n);
extern HVMValue HVMValue_makeChar(char n);
extern HVMValue HVMValue_makeBool(bool n);
extern HVMValue HVMValue_makeFloat(double n);
extern HVMValue HVMValue_makeString(char* str, uint32_t len);

// Utilidades
extern void printValue(HVMValue val);

#endif // VM_H
