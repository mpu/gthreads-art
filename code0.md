## Code 0: Foundations

Here we dive into the code to get a very small but effective implementation of green threads. We will use the knowledge of the ABI to craft a data structure representing an execution thread. This structure will then be used to interrupt and restore the control flow hence providing the base building block to get working user threads.

The code described here can be found in the [code0](https://github.com/mpu/gthreads/tree/code0) branch of the Github repository. A Makefile is included and should work on any platform having the GNU compilation toolkit installed.

### Annotated listing (gthr.c)

For this first version of the threading library, we simply use a single C file to store both the code of the library and the example. This is quite reasonable since everything fits in 133 lines.

!descr
To start with, let's include this bunch of headers. I use C99 so we have booleans and precise integer types. This will be convenient to explicit the size of variables used.

!code
!c
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

!descr
We first need to declare some constants useful in the rest of the code. To simplify, the number of green threads available is currently fixed to 4. This number includes the *bootstrap thread* which will be the only thread available when the program starts. The `StackSize` constant gives the size of a thread stack, I choose 4Mb, this should be more than sufficient for many applications.

!code
!c
enum {
	MaxGThreads = 4,
	StackSize = 0x400000,
};

!descr
This is getting serious, the structure gt describes what a green thread is from the threading library's point of view. The `ctx` member of a thread structure captures a CPU state. This member can be seen as a frozen execution context for the thread so it is meaningful only when the thread is in state `Ready`. You might have noticed that only callee save registers appear in a context;  more details about this will be given in `gtswtch` below.

For the time being, a thread structure can be in three states.

  * `Unused` - this thread structure is available for use.
  * `Running` - this is the state of the thread currently being run, there can only be one in this state.
  * `Ready` - this describes a valid thread whose execution is currently suspended, our scheduler must resume it in the future.

!code
!c
struct gt {
	struct gtctx {
		uint64_t rsp;
		uint64_t r15;
		uint64_t r14;
		uint64_t r13;
		uint64_t r12;
		uint64_t rbx;
		uint64_t rbp;
	} ctx;
	enum {
		Unused,
		Running,
		Ready,
	} st;
};

!descr
For simplicity, all the thread structures we will use will be stored in the `gttbl` array. At any point, when the library is initialized, the `gtcur` pointer points to the thread being currently executed.

!code
!c
static struct gt gttbl[MaxGThreads];
static struct gt *gtcur;

!descr
This is the list of functions that we will implement in this article, they provide the base threading API we will start with.

!code
!c
void        gtinit(void);
void        gtret(int ret);
void        gtswtch(struct gtctx *old, struct gtctx *new);
bool        gtyield(void);
static void gtstop(void);
int         gtgo(void (*f)(void));

!descr
The initialization of the library must be executed before any other task. It will simply allocate the thread 0 and mark it as running. This thread is a bit special because it is not created by the library: it exists from the very beginning of the execution of the program. You can see this as a bootstrap thread.

!code
!c
void
gtinit(void)
{
	gtcur = &gttbl[0];
	gtcur->st = Running;
}

!descr
When the user wants to stop the current thread, he calls the `gtret` function. This function must not return, so I give a hint to gcc.

We use the `gtyield` function which returns a boolean indicating if another thread is in the `Ready` state.

I decided to treat the main thread specially but this could be different. This thread will first wait to be the only runnable thread then exit the whole process with the passed return code.

If the current thread is not the bootstrap thread we simply mark the thread structure as unused and yield the CPU to another process. Note that this `gtyield` call must not return because the scheduler must choose to run a process in `Ready` state and we are now `Unused`. The assertion is safe since we know that by design the main thread remains runnable until the end of the program so the scheduler can always switch to it.

!code
!c
void __attribute__((noreturn))
gtret(int ret)
{
	if (gtcur != &gttbl[0]) {
		gtcur->st = Unused;
		gtyield();
		assert(!"reachable");
	}
	while (gtyield())
		;
	exit(ret);
}

!descr
The yielding function which is probably the most central and interesting is defined here. Its job can be divided in two parts.

  1. Find a new thread to run.
  2. Switch from the current thread to this new one.

The first part is implemented very naively, we will simply enumerate all threads after the current one and stop when we find one which is ready to run. In the case we are the only thread which can be run we return `false` to indicate it.

If a target thread is found, we store a pointer to its execution context in `new` and we store a pointer to ours in `old`. Then we set `gtcur` to the address of new thread gt structure. Finally we call the context switching function. This will store the current context in `old` and move to the `new` one.

Note that, seen this way, `gtswtch` never "returns" in the same thread. Indeed we simply move to the new execution context. However, there is one possible way for this call to return, namely if we are switched to from another thread! This will happen if the state of the current thread is `Ready` since our scheduler is a simple round-robin algorithm. On the contrary if the state of the current thread was `Unused` (this happens when we are called from `gtret`) then this switch has no chance to "return".

Basically if you got this, you grasped the essence of green threads!

!code
!c
bool
gtyield(void)
{
	struct gt *p;
	struct gtctx *old, *new;

	p = gtcur;
	while (p->st != Ready) {
		if (++p == &gttbl[MaxGThreads])
			p = &gttbl[0];
		if (p == gtcur)
			return false;
	}

	if (gtcur->st != Unused)
		gtcur->st = Ready;
	p->st = Running;
	old = &gtcur->ctx;
	new = &p->ctx;
	gtcur = p;
	gtswtch(old, new);
	return true;
}

!descr
This little static helper will be useful to create new threads in `gtgo`.

!code
!c
static void
gtstop(void) { gtret(0); }

!descr
Here is defined the function creating new green threads. Its task can be decomposed in three steps.

  1. Find an unused slot in the thread table.
  2. Create and setup a private stack for the new thread.
  3. Setup the execution context of the new thread and mark it as ready to run.

Finding an unused slot is a simple matter of linear search; if no slot is available we return -1 to the caller indicating a failure in the thread creation.

The stack is allocated via the regular C `malloc` function &mdash; remember that the stack is a simple block of memory.

What happens next is a bit tricky, we want the thread to start executing the function `f` when it will be scheduled. Since rip is not present in a context structure, we must use a trick. What we do is push the address of `f` on top of the stack &mdash; this way it will be used as return address for `gtswtch` and cause the desired jump. We will "return" directly into `f` after the first context switch!

If `f` returns, we don't want any bad thing to happen so we make the CPU return into `gtstop`. This function defined above will simply call `gtret` which will yield control to another thread and never return.

!code
!c
int
gtgo(void (*f)(void))
{
	char *stack;
	struct gt *p;

	for (p = &gttbl[0];; p++)
		if (p == &gttbl[MaxGThreads])
			return -1;
		else if (p->st == Unused)
			break;

	stack = malloc(StackSize);
	if (!stack)
		return -1;

	*(uint64_t *)&stack[StackSize -  8] = (uint64_t)gtstop;
	*(uint64_t *)&stack[StackSize - 16] = (uint64_t)f;
	p->ctx.rsp = (uint64_t)&stack[StackSize - 16];
	p->st = Ready;

	return 0;
}

!descr
And finally, the test code I promised you would be able to execute in the very first introduction article!

!code
!c
void
f(void)
{
	static int x;
	int i, id;

	id = ++x;
	for (i = 0; i < 10; i++) {
		printf("%d %d\n", id, i);
		gtyield();
	}
}

int
main(void)
{
	gtinit();
	gtgo(f);
	gtgo(f);
	gtret(1);
}

!end

### Annotated listing (gtswtch.S)

The switching function is written in assembly in a separate file for better control. From the C point of view it can be used as a regular function. Although, it is a special function since which manipulates control flow as first class objects (context structures). Two functions from the standard C also provide this kind of functionality `setjmp` and `longjmp`.

!descr
It is a trivial sequence of move instructions from and to memory. There is nothing deep here. Note that the order of registers in a C context structure is reflected here by offsets.

What is interesting is the set of registers we chose to represent a context. As noted above, they are the callee-save registers. Indeed, when the `gtswtch` function is called, the caller only relies on these registers, all the others can be trashed so they are not relevant to the current state. When we will be switched back, only these necessary registers will be restored &mdash; this is what allows the implementation of context switch to be super fast.

If you think a bit about it, you will probably find out that what has the most impressive consequences is the loading of rsp. This changes the whole call stack &mdash; which is essentially what a green thread is.

!code
!asm
gtswtch:

        mov     %rsp, 0x00(%rdi)
        mov     %r15, 0x08(%rdi)
        mov     %r14, 0x10(%rdi)
        mov     %r13, 0x18(%rdi)
        mov     %r12, 0x20(%rdi)
        mov     %rbx, 0x28(%rdi)
        mov     %rbp, 0x30(%rdi)

        mov     0x00(%rsi), %rsp
        mov     0x08(%rsi), %r15
        mov     0x10(%rsi), %r14
        mov     0x18(%rsi), %r13
        mov     0x20(%rsi), %r12
        mov     0x28(%rsi), %rbx
        mov     0x30(%rsi), %rbp

        ret

!end

## Epilogue

That was a long and hard to digest ride. The context handling can take a little while to fully grasp and the code implementing it is pretty tricky. Anyway I think this hundred lines of code is an excellent summary of what user threads are in their purest essence.

More complex libraries feature a better scheduler than ours (whose only virtue is to be 7 lines long). They have a more complex state for green threads and many concurrency abstractions. You are welcome to hack on this piece of code by cloning it in Github. The current code can be extended in many directions. I recommend trying to add exit codes in regular green threads (so the argument in `gtret` always makes sense) with some mechanism to get the exit code of a dead thread &mdash; you probably want to use something like Unix zombie processes for this. It is also a good challenge to add a parameter to the function started by `gtgo` to provide an API that looks a bit more like `pthread_create`.

I hope you got something out of this. If not I think that playing with gdb and the code is an excellent way to understand the mechanics of context switching. You can try to trace the execution of `gtyield` and see what happens when you backtrace before and after the `gtswtch` call. In some special cases, gdb might get lost after the context switch, try to understand what they are and how it relates to the fact the this function call is the very last instruction of `gtyield`.

Next time we will see what is at stake when we want to handle IO operations.