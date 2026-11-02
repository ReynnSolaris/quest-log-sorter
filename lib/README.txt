CommonLibF4 goes here as a git submodule:

    git submodule add https://github.com/libxse/commonlibf4 lib/commonlibf4
    git submodule update --init --recursive

xmake.lua does includes("lib/commonlibf4"), so the path and the lowercase
name both matter.

The --recursive matters too: commonlibf4 pulls in lib/commonlib-shared, which
is where the commonlibf4.plugin build rule actually lives. Without it you get
an "unknown rule" error rather than a missing-file one.
