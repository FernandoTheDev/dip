module runtime;

import vm;
import core.stdc.string : strcmp, memcpy;
import core.stdc.stdlib : malloc, free;
import core.stdc.stdio : printf;
import core.sys.posix.dlfcn;

@nogc:

alias FN_BUILTIN = HVMValue function(ref HVM vm, HVMValue* args, uint argc);
alias FN_FFI = HVMValue function(HVM* vm, HVMValue* args, uint argc);

__gshared void*[1] LIBS;

HVMValue fn_add(ref HVM vm, HVMValue* args, uint argc)
{
    check(argc == 2, "add() expects 2 arguments.");
    return HVMValue.makeInt(args[0].value.i32 + args[1].value.i32);
}

HVMValue fn_print(ref HVM vm, HVMValue* args, uint argc)
{
    printValue(args[0]);
    return HVMValue.makeBool(false);
}

HVMValue fn_libffi_open(ref HVM vm, HVMValue* args, uint argc)
{
    check(argc == 1, "libffi_open() expects 1 argument.");
    
    HVMString name = args[0].value.str;
    char* lib = name.value;
    
    void* ptr = dlopen(lib, RTLD_LAZY);
    if (ptr is null)
    {
        char* error = dlerror();
        printf("dlopen error: %s\n", error);
            return HVMValue.makeInt(-1);
    }
    
    LIBS[0] = ptr;
    
    return HVMValue.makeInt(0);
}

HVMValue fn_libffi_call(ref HVM vm, HVMValue* args, uint argc)
{
    check(argc >= 2, "libffi_call() expects at least 2 arguments (lib_name, fn_name).");
    
    long lib = args[0].value.i32;
    HVMString sym = args[1].value.str;
    char* fnName = sym.value;
    
    FN_FFI fn = cast(FN_FFI) dlsym(LIBS[lib], fnName);
    if (fn is null)
    {
        char* error = dlerror();
        printf("dlsym error for '%s': %s\n", fnName, error);
        return HVMValue.makeBool(false);
    }
    
    HVMValue val = fn(&vm, args + 2, argc - 2);
    return val;
}

HVMValue fn_libffi_cleanup(ref HVM vm, HVMValue* args, uint argc)
{
    foreach (lib; LIBS)
        if (lib !is null)
            dlclose(lib);
    return HVMValue.makeBool(true);
}

HVMValue fn_vm_pop(ref HVM vm, HVMValue* args, uint argc)
{
    return vm.pop();
}

HVMValue fn_count(ref HVM vm, HVMValue* args, uint argc)
{
    check(argc == 1, "count() expects 1 argument.");
    check(args[0].type == HVMType.Array, "count() expects an array.");
    return HVMValue.makeInt(args[0].value.arr.map.size());
}

struct BuiltinFn
{
    const char* name;
    FN_BUILTIN fn;
}

const BuiltinFn[] BUILTINS = [
    BuiltinFn("add", &fn_add),
    BuiltinFn("print", &fn_print),
    BuiltinFn("libffi_open", &fn_libffi_open),
    BuiltinFn("libffi_call", &fn_libffi_call),
    BuiltinFn("libffi_cleanup", &fn_libffi_cleanup),
    BuiltinFn("__vm_pop", &fn_vm_pop),
    BuiltinFn("count", &fn_count),
];

FN_BUILTIN findBuiltin(char* name)
{
    for (int i = 0; i < BUILTINS.length; i++)
        if (strcmp(name, BUILTINS[i].name) == 0)
            return BUILTINS[i].fn;
    return null;
}
