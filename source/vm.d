module vm;

@nogc:
extern (C):

import core.stdc.stdio, core.stdc.stdlib;
import hm;
import runtime;
import main;

alias FFI_FUNCTION = HVMValue function(HVMValue*, uint argc);

enum HVMType : ubyte
{
    Bool, //      i1  1 byte (1 bit)
    Char, //      i8  1 byte
    Int, //       i64 8 bytes
    Float, //     f64 8 bytes
    String, //    struct HVMString
    HashTable, // struct HVMHashTable
    Object, //    struct HVMObject
}

struct HVMString
{
    char* value;
    uint length;
}

struct HVMHashTable
{
}

struct HVMObject
{
}

union HVMLiteral
{
    long i32;
    byte i8; // char
    bool i1;
    double f32;
    HVMString str;
    HVMHashTable ht;
    HVMObject obj;
}

struct HVMValue
{
@nogc:
    HVMType type; // 1 byte
    HVMLiteral value;

    pragma(inline, true)
    pragma(mangle, "HVMValue_makeInt")
    static HVMValue makeInt(long n)
    {
        HVMValue v = HVMValue(HVMType.Int);
        v.value.i32 = n;
        return v;
    }

    pragma(inline, true)
    static HVMValue makeChar(int n)
    {
        return makeChar(cast(char) n);
    }

    pragma(inline, true);
    pragma(mangle, "HVMValue_makeChar")
    static HVMValue makeChar(char n)
    {
        HVMValue v = HVMValue(HVMType.Char);
        v.value.i8 = n;
        return v;
    }

    pragma(inline, true)
    pragma(mangle, "HVMValue_makeBool")
    static HVMValue makeBool(bool n)
    {
        HVMValue v = HVMValue(HVMType.Bool);
        v.value.i1 = n;
        return v;
    }

    pragma(inline, true)
    pragma(mangle, "HVMValue_makeString")
    static HVMValue makeString(char* str, uint len)
    {
        HVMValue v = HVMValue(HVMType.String);
        v.value.str = HVMString(str, len);
        return v;
    }

    pragma(inline, true)
    pragma(mangle, "HVMValue_makeFloat")
    static HVMValue makeFloat(double n)
    {
        HVMValue v = HVMValue(HVMType.Float);
        v.value.f32 = n;
        return v;
    }
}

enum HVMOpCode : ubyte
{
    // core
    Store, // store "x"
    Load, // load "x"
    Loadk, // carrega uma constante do pool
    Loadkx, // carregar uma constante com IDX grande do pool
    Call, // chamada em função normal com `ret`
    Callb, // chamada em função builtin
    Callf, // chamada em função ffi
    Ret, // retorna pro `pc` anterior
    Echo,

    // genericos pra qualquer tipo prevalecendo o tipo maior, suportam fastPath para operações com o mesmo tipo
    // prefixo B indica BitWise
    Add, // +
    Sub, // -
    Mul, // *
    Div, // /
    Mod, // %

    BShl, // >>
    BShll, // >>>
    BShr, // <<
    BXor, // ^
    BAnd, // &
    Bor, // |
    BNot, // ~

    Jmp,
    Jz, //  jmp if zero (false)
    Jnz, // jmp if not zero (true)
    // toda condição retorna um bool que pode ser 1 ou 0 (true ou false)
    Lt, // <
    Gt, // >
    Lte, // <=
    Gte, // >=
    Eq, // ==
    Neq, // !=

    Hlt, // Halt
}

struct FrameCall
{
    HashMap!(string, HVMValue)* localContext;
    uint retAddr;
}

struct HVM
{
@nogc:
    uint* program; // programa
    uint pc; // contador do programa
    uint programSize; // tamanho do programa
    HVMValue* constantPool; // mapa de constantes
    uint constantPoolSize; // tamanho do mapa de constantes
    ubyte STACK_LIMIT = 255;
    HVMValue[255] stack = []; // a pilha do programa
    uint stackSize;
    HashMap!(string, HVMValue)* context;
    FrameCall[255] callStack;
    uint callStackSize = 0;
    bool clean = true;

    // pragma(mangle, "HVM_create")
    // this(uint* program, uint programSize, HVMValue* constantPool, uint constantPoolSize, bool clean = true)
    // {
    //     this.program = program;
    //     this.programSize = programSize;
    //     this.constantPool = constantPool;
    //     this.constantPoolSize = constantPoolSize;
    //     this.clean = clean;
    //     context = cast(HashMap!(string, HVMValue)*) malloc(HashMap!(string, HVMValue).sizeof);
    //     context.initialize(255);
    // }

    ~this()
    {
        this.clear();
    }

    pragma(inline, true)
    pragma(mangle, "HVM_clear")
    void clear()
    {
        if (clean)
        {
            if (program !is null)
                free(program);
            if (constantPool !is null)
                free(constantPool);
        }

        for (uint i = 0; i < callStackSize; i++)
            if (callStack[i].localContext !is null)
                free(callStack[i].localContext);

        if (context !is null)
            free(context);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_error")
    void error(string msg)
    {
        printf("HVM Internal error: %s", cast(const char*) msg);
        exit(EXIT_FAILURE);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_pop")
    HVMValue pop()
    {
        if (stackSize < 1)
            this.error("Stack Underflow.");
        return stack[--stackSize];
    }

    pragma(inline, true)
    pragma(mangle, "HVM_push")
    void push(HVMValue val)
    {
        if (stackSize == STACK_LIMIT)
            this.error("Stack Overflow.");
        stack[stackSize++] = val;
    }

    pragma(mangle, "HVM_run")
    void run()
    {
        while (pc < programSize)
        {
            uint instr = program[pc++];
            ubyte opcode = instr & 0xFF;

            // printf("opcode: %d\n", opcode);

            final switch (opcode)
            {
            case HVMOpCode.Loadk:
                opLoadk(instr >> 8 & 0xFFFF);
                continue;
            case HVMOpCode.Store:
                opStore();
                continue;
            case HVMOpCode.Load:
                opLoad();
                continue;
            case HVMOpCode.Add:
                opAdd();
                continue;
            case HVMOpCode.Sub:
                opSub();
                continue;
            case HVMOpCode.Mul:
                opMul();
                continue;
            case HVMOpCode.Div:
                opDiv();
                continue;
            case HVMOpCode.Echo:
                opEcho();
                continue;
            case HVMOpCode.Eq:
                opEq();
                continue;
            case HVMOpCode.Jmp:
                opJmp(instr >> 8 & 0xFFFF);
                continue;
            case HVMOpCode.Jz:
                opJz(instr >> 8 & 0xFFFF);
                continue;
            case HVMOpCode.Jnz:
                opJnz(instr >> 8 & 0xFFFF);
                continue;
            case HVMOpCode.Lt:
                opLt();
                continue;
            case HVMOpCode.Mod:
                opMod();
                continue;
            case HVMOpCode.Call:
                opCall(instr >> 8 & 0xFFFF);
                continue;
            case HVMOpCode.Callb:
                opCallb(instr >> 8 & 0xFFFF);
                continue;
            case HVMOpCode.Callf:
                opCallf(instr >> 8 & 0xFFFF);
                continue;
            case HVMOpCode.Ret:
                opRet();
                continue;

            case HVMOpCode.BShl:
            case HVMOpCode.BShll:
            case HVMOpCode.BShr:
            case HVMOpCode.BXor:
            case HVMOpCode.BAnd:
            case HVMOpCode.BNot:
            case HVMOpCode.Bor:

            case HVMOpCode.Gt:
            case HVMOpCode.Lte:
            case HVMOpCode.Gte:
            case HVMOpCode.Neq:

            case HVMOpCode.Loadkx:
            case HVMOpCode.Hlt:
                return;
            }
        }
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opCallf")
    void opCallf(ushort argc)
    {
        HVMValue funcName = pop();
        check(funcName.type == HVMType.String, "Function name must be string");

        HVMString str = funcName.value.str;
        string name = cast(string)str.value[0..str.length];
        FN_FFI* fn = FFI_FUNCTIONS.get(name);
        check(fn !is null, "FFI function not found");

        HVMValue[16] staticBuffer; 
        HVMValue* args;

        if (argc <= 16)
            args = staticBuffer.ptr;
        else
            args = cast(HVMValue*) malloc(HVMValue.sizeof * argc);
        
        for (int i = argc - 1; i >= 0; i--)
            args[i] = pop();

        HVMValue result = (*fn)(&this, args, argc);
        if (argc > 16)
            free(args);
        push(result);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opCallb")
    void opCallb(ushort argc)
    {
        HVMValue funcName = pop();
        check(funcName.type == HVMType.String, "Function name must be string");

        FN_BUILTIN fn = findBuiltin(funcName.value.str.value);
        check(fn !is null, "Builtin function not found");

        HVMValue[16] staticBuffer; 
        HVMValue* args;

        if (argc <= 16)
            args = staticBuffer.ptr;
        else
            args = cast(HVMValue*) malloc(HVMValue.sizeof * argc);

        for (int i = argc - 1; i >= 0; i--)
            args[i] = pop();

        HVMValue result = fn(this, args, argc);
        if (argc > 16)
            free(args);
        push(result);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opCall")
    void opCall(uint addr)
    {
        if (callStackSize >= 255)
            error("Call stack overflow.");

        callStack[callStackSize].retAddr = pc;
        callStack[callStackSize].localContext = context;
        callStackSize++;

        context = cast(HashMap!(string, HVMValue)*) malloc(HashMap!(string, HVMValue).sizeof);
        context.initialize(255);
        pc = addr;
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opRet")
    void opRet()
    {
        if (callStackSize == 0)
            error("Return without call.");

        HVMValue retVal = pop();
        callStackSize--;

        if (context !is null)
            free(context);

        context = callStack[callStackSize].localContext;
        pc = callStack[callStackSize].retAddr;
        push(retVal);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opJz")
    void opJz(uint addr)
    {
        HVMValue val = pop();
        if (val.value.i1 == false)
            pc = addr;
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opJnz")
    void opJnz(uint addr)
    {
        HVMValue val = pop();
        if (val.value.i1 != false)
            pc = addr;
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opJmp")
    void opJmp(uint addr)
    {
        pc = addr;
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opEcho")
    void opEcho()
    {
        printValue(pop());
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opStore")
    void opStore()
    {
        HVMValue idx = pop();
        HVMValue val = pop();
        string key = cast(string) idx.value.str.value[0 .. idx.value.str.length];
        context.put(key, val);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opLoad")
    void opLoad()
    {
        HVMValue idx = pop();
        string key = cast(string) idx.value.str.value[0 .. idx.value.str.length];
        HVMValue* val = context.get(key);
        if (val !is null)
            push(*val);
        else
            push(HVMValue.init);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opMod")
    void opMod()
    {
        HVMValue l = pop();
        HVMValue r = pop();
        if (l.type >= HVMType.String || r.type >= HVMType.String)
            error("It is not possible to perform the addition operation with these types.");
        if (l.type == r.type) switch (l.type)
        {
        case HVMType.Int:
            push(HVMValue.makeInt(l.value.i32 % r.value.i32));
            return;
        case HVMType.Char:
            push(HVMValue.makeChar(cast(byte)(l.value.i8 % r.value.i8)));
            return;
        case HVMType.Float:
            push(HVMValue.makeFloat(l.value.f32 % r.value.f32));
            return;
        default:
            error("Unknown type in '%' operation.");
            return;
        }
        opModSlowPath(l, r);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opModSlowPath")
    void opModSlowPath(HVMValue l, HVMValue r)
    {
        HVMType t = l.type > r.type ? l.type : r.type;
        switch (t)
        {
        case HVMType.Int:
            push(HVMValue.makeInt(toInt(l).value.i32 % toInt(r).value.i32));
            return;
        case HVMType.Char:
            push(HVMValue.makeChar(cast(byte)(toChar(l)
                    .value.i8 % toChar(r).value.i8)));
            return;
        case HVMType.Float:
            push(HVMValue.makeFloat(toFloat(l).value.f32 % toFloat(r).value.f32));
            return;
        default:
            error("Error on '%' slow path.");
            break;
        }
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opLt")
    void opLt()
    {
        HVMValue l = pop();
        HVMValue r = pop();
        if (l.type >= HVMType.String || r.type >= HVMType.String)
            error("It is not possible to perform the addition operation with these types.");
        if (l.type == r.type) switch (l.type)
        {
        case HVMType.Int:
            push(HVMValue.makeBool(l.value.i32 < r.value.i32));
            return;
        case HVMType.Char:
            push(HVMValue.makeBool(cast(byte)(l.value.i8 < r.value.i8)));
            return;
        case HVMType.Float:
            push(HVMValue.makeBool(l.value.f32 < r.value.f32));
            return;
        default:
            error("Unknown type in '<' operation.");
            return;
        }
        opLtSlowPath(l, r);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opLtSlowPath")
    void opLtSlowPath(HVMValue l, HVMValue r)
    {
        HVMType t = l.type > r.type ? l.type : r.type;
        switch (t)
        {
        case HVMType.Int:
            push(HVMValue.makeBool(toInt(l).value.i32 < toInt(r).value.i32));
            return;
        case HVMType.Char:
            push(HVMValue.makeBool(cast(byte)(toChar(l)
                    .value.i8 < toChar(r).value.i8)));
            return;
        case HVMType.Float:
            push(HVMValue.makeBool(toFloat(l).value.f32 < toFloat(r).value.f32));
            return;
        default:
            error("Error on '<' slow path.");
            break;
        }
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opEq")
    void opEq()
    {
        HVMValue l = pop();
        HVMValue r = pop();
        if (l.type >= HVMType.String || r.type >= HVMType.String)
            error("It is not possible to perform the addition operation with these types.");
        if (l.type == r.type) switch (l.type)
        {
        case HVMType.Int:
            push(HVMValue.makeBool(l.value.i32 == r.value.i32));
            return;
        case HVMType.Char:
            push(HVMValue.makeBool(cast(byte)(l.value.i8 == r.value.i8)));
            return;
        case HVMType.Float:
            push(HVMValue.makeBool(l.value.f32 == r.value.f32));
            return;
        default:
            error("Unknown type in '==' operation.");
            return;
        }
        opEqSlowPath(l, r);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opEqSlowPath")
    void opEqSlowPath(HVMValue l, HVMValue r)
    {
        HVMType t = l.type > r.type ? l.type : r.type;
        switch (t)
        {
        case HVMType.Int:
            push(HVMValue.makeBool(toInt(l).value.i32 == toInt(r).value.i32));
            return;
        case HVMType.Char:
            push(HVMValue.makeBool(cast(byte)(toChar(l)
                    .value.i8 == toChar(r).value.i8)));
            return;
        case HVMType.Float:
            push(HVMValue.makeBool(toFloat(l).value.f32 == toFloat(r).value.f32));
            return;
        default:
            error("Error on '==' slow path.");
            break;
        }
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opAdd")
    void opAdd()
    {
        HVMValue l = pop();
        HVMValue r = pop();
        if (l.type >= HVMType.String || r.type >= HVMType.String)
            error("It is not possible to perform the addition operation with these types.");
        if (l.type == r.type) switch (l.type)
        {
        case HVMType.Int:
            push(HVMValue.makeInt(l.value.i32 + r.value.i32));
            return;
        case HVMType.Char:
            push(HVMValue.makeChar(cast(byte)(l.value.i8 + r.value.i8)));
            return;
        case HVMType.Float:
            push(HVMValue.makeFloat(l.value.f32 + r.value.f32));
            return;
        default:
            error("Unknown type in addition operation.");
            return;
        }
        opAddSlowPath(l, r);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opAddSlowPath")
    void opAddSlowPath(HVMValue l, HVMValue r)
    {
        HVMType t = l.type > r.type ? l.type : r.type;
        switch (t)
        {
        case HVMType.Int:
            push(HVMValue.makeInt(toInt(l).value.i32 + toInt(r).value.i32));
            return;
        case HVMType.Char:
            push(HVMValue.makeChar(cast(byte)(toChar(l)
                    .value.i8 + toChar(r).value.i8)));
            return;
        case HVMType.Float:
            push(HVMValue.makeFloat(toFloat(l).value.f32 + toFloat(r).value.f32));
            return;
        default:
            error("Error on add slow path.");
            break;
        }
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opSub")
    void opSub()
    {
        HVMValue l = pop();
        HVMValue r = pop();
        // evita que strings ou outros tipos não literais sejam passados aqui
        if (l.type >= HVMType.String || r.type >= HVMType.String)
            error("It is not possible to perform subtraction with these types.");
        // tenta fastPath
        if (l.type == r.type) switch (l.type)
        {
        case HVMType.Int:
            push(HVMValue.makeInt(l.value.i32 - r.value.i32));
            return;
        case HVMType.Char:
            push(HVMValue.makeChar(cast(byte)(l.value.i8 - r.value.i8)));
            return;
        case HVMType.Float:
            push(HVMValue.makeFloat(l.value.f32 - r.value.f32));
            return;
        default:
            error("Unknown type in subtraction operation.");
            return;
        }
        opSubSlowPath(l, r);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opSubSlowPath")
    void opSubSlowPath(HVMValue l, HVMValue r)
    {
        HVMType t = l.type > r.type ? l.type : r.type;
        // printf("[DEBUG] slow path\n");
        switch (t)
        {
        case HVMType.Int:
            push(HVMValue.makeInt(toInt(l).value.i32 - toInt(r).value.i32));
            return;
        case HVMType.Char:
            push(HVMValue.makeChar(toChar(l).value.i8 - toChar(r).value.i8));
            return;
        case HVMType.Float:
            push(HVMValue.makeFloat(toFloat(l).value.f32 - toFloat(r).value.f32));
            return;
        default:
            error("Error on sub slow path.");
            break;
        }
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opMul")
    void opMul()
    {
        HVMValue l = pop();
        HVMValue r = pop();
        // evita que strings ou outros tipos não literais sejam passados aqui
        if (l.type >= HVMType.String || r.type >= HVMType.String)
            error("It is not possible to perform multiplication operations with these types.");
        // tenta fastPath
        if (l.type == r.type) switch (l.type)
        {
        case HVMType.Int:
            push(HVMValue.makeInt(l.value.i32 * r.value.i32));
            return;
        case HVMType.Char:
            push(HVMValue.makeChar(cast(byte)(l.value.i8 * r.value.i8)));
            return;
        case HVMType.Float:
            push(HVMValue.makeFloat(l.value.f32 * r.value.f32));
            return;
        default:
            error("Unknown type in multiplication operation.");
            return;
        }
        opMulSlowPath(l, r);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opMulSlowPath")
    void opMulSlowPath(HVMValue l, HVMValue r)
    {
        HVMType t = l.type > r.type ? l.type : r.type;
        // printf("[DEBUG] slow path\n");
        switch (t)
        {
        case HVMType.Int:
            push(HVMValue.makeInt(toInt(l).value.i32 * toInt(r).value.i32));
            return;
        case HVMType.Char:
            push(HVMValue.makeChar(toChar(l).value.i8 * toChar(r).value.i8));
            return;
        case HVMType.Float:
            push(HVMValue.makeFloat(toFloat(l).value.f32 * toFloat(r).value.f32));
            return;
        default:
            error("Error on mul slow path.");
            break;
        }
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opDiv")
    void opDiv()
    {
        HVMValue l = pop();
        HVMValue r = pop();
        // evita que strings ou outros tipos não literais sejam passados aqui
        if (l.type >= HVMType.String || r.type >= HVMType.String)
            error("It is not possible to perform the division operation with these data types.");
        // tenta fastPath
        if (l.type == r.type) switch (l.type)
        {
        case HVMType.Int:
            check(r.value.i32 != 0, "Div by zero.");
            push(HVMValue.makeInt(l.value.i32 / r.value.i32));
            return;
        case HVMType.Char:
            check(r.value.i8 != 0, "Div by zero.");
            push(HVMValue.makeChar(cast(byte)(l.value.i8 / r.value.i8)));
            return;
        case HVMType.Float:
            check(r.value.f32 != 0.0, "Div by zero.");
            push(HVMValue.makeFloat(l.value.f32 / r.value.f32));
            return;
        default:
            error("Unknown type in the division operation.");
            return;
        }
        opDivSlowPath(l, r);
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opDivSlowPath")
    void opDivSlowPath(HVMValue l, HVMValue r)
    {
        // define o tipo pelo nivel de cada tipo
        // a enum de tipos está na ordem certa
        // isso é mais que suficiente pra cast automatico
        HVMType t = l.type > r.type ? l.type : r.type;
        // printf("[DEBUG] slow path\n");

        HVMValue lConverted, rConverted;

        switch (t)
        {
        case HVMType.Int:
            lConverted = toInt(l);
            rConverted = toInt(r);
            check(rConverted.value.i32 != 0, "Div by zero.");
            push(HVMValue.makeInt(lConverted.value.i32 / rConverted.value.i32));
            return;

        case HVMType.Char:
            lConverted = toChar(l);
            rConverted = toChar(r);
            check(rConverted.value.i8 != 0, "Div by zero.");
            push(HVMValue.makeChar(lConverted.value.i8 / rConverted.value.i8));
            return;

        case HVMType.Float:
            lConverted = toFloat(l);
            rConverted = toFloat(r);
            check(rConverted.value.f32 != 0.0, "Div by zero.");
            push(HVMValue.makeFloat(lConverted.value.f32 / rConverted.value.f32));
            return;

        default:
            error("Error on div slow path.");
            break;
        }
    }

    pragma(inline, true)
    pragma(mangle, "HVM_toInt")
    HVMValue toInt(HVMValue val)
    {
        switch (val.type)
        {
        case HVMType.Int:
            return val;
        case HVMType.Char:
            return HVMValue.makeInt(cast(long) val.value.i8);
        case HVMType.Float:
            return HVMValue.makeInt(cast(long) val.value.f32);
        case HVMType.Bool:
            return HVMValue.makeInt(cast(long) val.value.i1);
        default:
            error("It's not possible to convert this type to an integer.");
            break;
        }
        // nunca é retornando porque vai dar erro antes
        return HVMValue.init;
    }

    pragma(inline, true)
    pragma(mangle, "HVM_toFloat")
    HVMValue toFloat(HVMValue val)
    {
        switch (val.type)
        {
        case HVMType.Float:
            return val;
        case HVMType.Int:
            return HVMValue.makeFloat(cast(double) val.value.i32);
        case HVMType.Char:
            return HVMValue.makeFloat(cast(double) val.value.i8);
        case HVMType.Bool:
            return HVMValue.makeFloat(cast(double) val.value.i1);
        default:
            error("It's not possible to convert this type to a float.");
            break;
        }
        return HVMValue.init;
    }

    pragma(inline, true)
    pragma(mangle, "HVM_toBool")
    HVMValue toBool(HVMValue val)
    {
        switch (val.type)
        {
        case HVMType.Bool:
            return val;
        case HVMType.Int:
            return HVMValue.makeBool(val.value.i32 != 0);
        case HVMType.Char:
            return HVMValue.makeBool(val.value.i8 != 0);
        case HVMType.Float:
            return HVMValue.makeBool(val.value.f32 != 0.0f);
        default:
            error("It's not possible to convert this type to a bool.");
            break;
        }
        return HVMValue.init;
    }

    pragma(inline, true)
    pragma(mangle, "HVM_toChar")
    HVMValue toChar(HVMValue val)
    {
        switch (val.type)
        {
        case HVMType.Char:
            return val;
        case HVMType.Int:
            check(val.value.i32 >= byte.min && val.value.i32 <= byte.max, "Char overflow/underflow.");
            return HVMValue.makeChar(cast(byte) val.value.i32);
        case HVMType.Float:
            return HVMValue.makeChar(cast(byte) val.value.f32);
        case HVMType.Bool:
            return HVMValue.makeChar(cast(byte) val.value.i1);
        default:
            error("It's not possible to convert this type to a char.");
            break;
        }
        return HVMValue.init;
    }

    pragma(inline, true)
    string typeToString(HVMType t)
    {
        switch (t)
        {
        case HVMType.String:
            return "string";
        case HVMType.Int:
            return "int";
        case HVMType.Float:
            return "float";
        case HVMType.Char:
            return "char";
        case HVMType.Bool:
            return "bool";
        default:
            return "<err>";
        }
    }

    pragma(inline, true)
    pragma(mangle, "HVM_opLoadk")
    void opLoadk(ushort idx)
    {
        if (idx > constantPoolSize || constantPoolSize == 0)
            error("The passed index exceeds the size of the constant map.");
        if (stackSize == STACK_LIMIT)
            error(
                "The stack is already full to its maximum limit, it is not possible to perform a 'Loadk'.");
        stack[stackSize++] = constantPool[idx];
    }
}

pragma(mangle, "HVM_create")
HVM* HVM_create(uint* program, uint programSize, HVMValue* constantPool, uint constantPoolSize, bool clean)
{
    HVM* vm = cast(HVM*) malloc(HVM.sizeof);
    if (vm is null)
    {
        printf("[DEBUG] malloc failed\n");
        return null;
    }

    vm.program = program;
    vm.programSize = programSize;
    vm.constantPool = constantPool;
    vm.constantPoolSize = constantPoolSize;
    vm.clean = clean;
    vm.pc = 0;
    vm.stackSize = 0;
    vm.callStackSize = 0;
    vm.STACK_LIMIT = 255;
    vm.callStackSize = 0;

    for (uint i = 0; i < vm.STACK_LIMIT; i++)
        vm.stack[i] = HVMValue.init;

    vm.context = cast(HashMap!(string, HVMValue)*) malloc(HashMap!(string, HVMValue).sizeof);
    if (vm.context is null)
    {
        free(vm);
        return null;
    }
    vm.context.initialize(255);

    return vm;
}

pragma(inline, true)
pragma(mangle, "check")
void check(bool result, string message)
{
    if (result)
        return;
    printf("HVM Error: %s\n", cast(char*) message);
    exit(EXIT_FAILURE);
}

pragma(inline, true)
pragma(mangle, "printValue")
void printValue(HVMValue val)
{
    switch (val.type)
    {
    case HVMType.String:
        printf("%s", val.value.str.value);
        break;
    case HVMType.Int:
        printf("%lld", val.value.i32);
        break;
    case HVMType.Float:
        printf("%f", val.value.f32);
        break;
    case HVMType.Char:
        printf("%c", val.value.i8);
        break;
    case HVMType.Bool:
        printf("%s", val.value.i1 ? cast(char*) "true" : cast(char*) "false");
        break;
    default:
        printf("<err>");
        break;
    }
}
