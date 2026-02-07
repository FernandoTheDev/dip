// gcc -shared -fPIC -o libtest.so test.c -I. -L. -ldip
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test.h"

HVMValue hello(HVM* vm, HVMValue* argv, uint32_t argc)
{
    HVMString str = argv[0].value.str;
    printf("Hello %s!\n", str.value);
    char* s = "SixSeveeen\n";
    HVM_push(vm, HVMValue_makeString(s, strlen(s)));
    return HVMValue_makeBool(true);
}
