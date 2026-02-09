# Cleanup tasks

Create a macro for Objective C block creation, to avoid the boilerplate code below. Something like: 

```
block_context = context;
block.isa = xx _NSConcreteGlobalBlock;
block.invoke = cast(*void)on_commit_feedback;
```
