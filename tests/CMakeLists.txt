include(FetchContent)
FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.14.0
)
FetchContent_MakeAvailable(googletest)

add_executable(test_imgproc test_imgproc.cpp)

target_link_libraries(test_imgproc PRIVATE
    GTest::gtest_main
    OpenCV::opencv_imgproc
    OpenCV::opencv_core
)

ep_target_add_compile_deps(test_imgproc)

target_enable_warnings(test_imgproc)

include(GoogleTest)
gtest_discover_tests(test_imgproc)
