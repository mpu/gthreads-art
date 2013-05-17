## Introduction

Green threads or userland threads (depending on your generation) provide high efficiency concurrency in a lot of mainstream languages. To only cite a few, CPython (via external libraries), Haskell, Go and Erlang are users of this technique. This series of short articles will expose the core ideas that rule this concurrency primitive.

I will try to make this tutorial self contained and with very few prerequisites. During the course of my explanations, you will have the occasion to implement your own green thread machinery for C on the x86-64 architecture.

I provide a [reference implementation](https://github.com/mpu/gthreads) hosted by Github so you can play with working code. This tutorial is divided in small sections &mdash; some parts correspond to branches in the git repository, their title start with "Code" followed by a number. For instance, "Code 0" will correspond to the code0 branch.

If you find any typo or have any suggestion about this tutorial, you can fill an [issue](https://github.com/mpu/gthreads-art/issues/new) on the [Github page of the tutorial](https://github.com/mpu/gthreads-art). Even better, if you want to make some modifications: fork the tutorial's repository and submit a pull request, I will be glad to integrate it here.

The full tutorial is not yet complete since I am not sure what I want to develop after having presented the base. The plan is to investigate and develop more topics once I get feedback from you for the first parts. Going through current implementations' code is also an alternative for further articles.

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