## Introduction

Green threads or userland threads (depending on your generation) provide high efficiency concurrency in a lot of mainstream languages. To only cite a few, CPython, Haskell, Go, Java and Ruby are users of this technique. This series of short articles will expose the core ideas that rule this concurrency primitive.

I will try to make this tutorial self contained and with very few prerequisites. During the course of my explanations, you will have the occasion to implement your own green thread machinery for C on the x86-64 architecture.

**TODO**: Speak about the organization. I provide a [reference implementation](http://github.com/mpu/gthreads) hosted by Github so you can get and play with working code.


## Definition and examples

> Green threads are threads that are scheduled by a virtual machine (VM) instead of natively by the underlying operating system.

This definition from Wikipedia raises several points. First and unsurprisingly green threads are threads: they can be seen as lightweight processes executed concurrently and sharing the same address space. Second, they are provided by a user mode program, meaning that we do not need to hack the kernel in order to implement them!

The definition mentions a virtual machine, this is not exactly accurate in my opinion, since for instance Go does not have a virtual machine. I would rather say an *execution environment* or more simply, a *runtime*.

At this point you may wonder why we are interested in userland threads while every modern kernel provides a functional threading API. So here is a list of some of the coolest advantages they feature:

  * Starting a green thread is super cheap (much cheaper than starting a kernel thread) and fast.
  * Switching from one green thread to another is much faster than switching between kernel threads.
  * They are the technology that allows Go to start hundreds of thousands of goroutines at high speed with low a memory footprint!
  * Finally, they are fun to implement and give a good idea of some techniques used in OS programming.

Obviously, there is no such thing as a free lunch, green threads come with their share of complexities and restrictions.

  * Only asynchronous IO is allowed (but we can emulate blocking system calls, as we will see).
  * In their simplest form, they cannot exploit multi processor parallelism (but we will see how to lift this restriction).
  * They are hard to implement and debug, yep, as I said they reuse kernel techniques!

To make this definition more concrete here is a simple example of C code that you will soon be able to run on your machine and which makes use of green threads, all thread related functions are prefixed by "gt".

	!c
	void f(void) {
		static int x;		/* this variable is shared */
		int i, id;

		id = ++x;			/* compute our thread ID */
		for (i = 0; i < 10; i++) {
			printf("%d %d\n", id, i);
			gtyield();		/* yield CPU to another green thread */
		}
	}

	int main(void) {
		gtinit();
		gtgo(f);			/* start the first thread */
		gtgo(f);			/* start the second thread */
		gtret(1);			/* wait for both and return 1 */
	}

This small program will start two green threads, wait for them to finish and return 1. The two green threads both execute the function `f` and are started by the `gtgo` calls. Calling `gtgo` with a function pointer as argument will start this function but it will not wait for the result and return immediately. The function `gtret` will wait that all started threads end then exit the program returning the integer it was given as argument. The `gtyield` function we have in the loop politely signals that, if necessary, the current thread can be interrupted to run the code of another thread; the current thread is not suspended by this call, i.e. it will automatically continue even if another thread is temporarily scheduled to run.

The first spawned thread will print digits 0 to 9 prefixed by a 1 and the second will print them prefixed by a 2. When the above program is executed, the two sequences are printed interleaved, this is the magic of threads! We are able to express multiple independent processes that run "at the same time".