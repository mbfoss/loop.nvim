return {
    cmake_path = "cmake",
    ctest_path = "ctest",
    profiles =
    {
        {
            name = "Debug",
            build_type = "Debug",
            source_dir = "${PROJDIR}",
            build_dir = "${PROJDIR}/build/Debug",
            configure_args = {"-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"},
            prob_matcher = "$gcc",
            build_tool_args = {"-j4"},
        },
        {
            name = "Release",
            build_type = "Release",
            source_dir = "${PROJDIR}",
            build_dir = "${PROJDIR}/build/Release",
            configure_args = {"-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"},
            prob_matcher = "$gcc",
            build_tool_args = {"-j4"},
        }
    }
}
