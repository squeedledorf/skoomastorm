# -*- cmake -*-

project(llrender)

include(00-Common)
include(OpenGL)
include(FreeType)
include(LLCommon)
include(LLImage)
include(LLWindow)

set(llrender_SOURCE_FILES
    alsamplerstate.cpp
    altexture3d.cpp
    altextureslot.cpp
    aluniformbuffer.cpp
    llcubemap.cpp
    llcubemaparray.cpp
    llfontbitmapcache.cpp
    llfontfreetype.cpp
    llfontfreetypesvg.cpp
    llfontgl.cpp
    llfontvertexbuffer.cpp
    llfontregistry.cpp
    llgl.cpp
    llglslshader.cpp
    llgltexture.cpp
    llimagegl.cpp
    llrender.cpp
    llrender2dutils.cpp
    llrendernavprim.cpp
    llrendersphere.cpp
    llrendertarget.cpp
    llshadermgr.cpp
    lltexture.cpp
    lltexturemanagerbridge.cpp
    lluiimage.cpp
    llvertexbuffer.cpp
    llglcommonfunc.cpp
    )
    
set(llrender_HEADER_FILES
    CMakeLists.txt

    alsamplerstate.h
    altexture3d.h
    altextureslot.h
    aluniformbuffer.h
    glcorearb/GL/glcorearb.h
    llcubemap.h
    llcubemaparray.h
    llfontgl.h
    llfontvertexbuffer.h
    llfontfreetype.h
    llfontfreetypesvg.h
    llfontbitmapcache.h
    llfontregistry.h
    llgl.h
    llglheaders.h
    llglslshader.h
    llglstates.h
    llgltexture.h
    llgltypes.h
    llimagegl.h
    llrender.h
    llrender2dutils.h
    llrendernavprim.h
    llrendersphere.h
    llrendertarget.h
    llshadermgr.h
    lltexture.h
    lltexturemanagerbridge.h
    lluiimage.h
    lluiimage.inl
    llvertexbuffer.h
    llglcommonfunc.h
    )

list(APPEND llrender_SOURCE_FILES ${llrender_HEADER_FILES})

if (BUILD_HEADLESS)
  add_library (llrenderheadless
    ${llrender_SOURCE_FILES}
    )

  set_property(TARGET llrenderheadless
    PROPERTY COMPILE_DEFINITIONS LL_MESA=1 LL_MESA_HEADLESS=1
      )

  target_link_libraries(llrenderheadless
          llcommon
          llimage
          llmath
          llrender
          llxml
          llfilesystem
          )
endif (BUILD_HEADLESS)

add_library (llrender ${llrender_SOURCE_FILES})
ss_hot_loop_codegen(llrender) # <SS:Nexii> see indra/cmake/00-Common.cmake
target_include_directories( llrender  INTERFACE   ${CMAKE_CURRENT_SOURCE_DIR})

set_property(TARGET llrender PROPERTY POSITION_INDEPENDENT_CODE ON)

# Libraries on which this library depends, needed for Linux builds
# Sort by high-level to low-level
target_link_libraries(llrender
        llcommon
        llimage
        llmath
        llfilesystem
        llxml
        llwindow
        ll::freetype
        )

# SKOOMA-PORT: GL entry points are function pointers resolved at runtime (Alchemy's loader,
# llglheaders.h LL_GL_FUNC_POINTER), so Linux does not link libGL; SDL loads the driver.
# Windows keeps opengl32 for wglGetProcAddress and the GL 1.1 fallbacks.
if (WINDOWS)
  target_link_libraries(llrender OpenGL::GL)
endif ()
# Khronos GL/glcorearb.h, vendored: the glext package ships glext.h but not the core header.
target_include_directories(llrender PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/glcorearb)

