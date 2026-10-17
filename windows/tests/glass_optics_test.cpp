// Numerical regression for the inset rectangle caused by diagonal normals on
// mesh rows/columns exactly one corner radius inside the straight window edges.
#include "../runner/glass_optics.h"

#include <array>
#include <cstdio>

namespace {
using orion::glass::float2;
using orion::glass::length;

bool CheckNormal(const char* name,float2 pixel,float2 size,float radius,float2 expected) {
  const auto actual=orion::glass::DistanceDirection(pixel-size*.5f,size*.5f,radius);
  const float error=length(actual-expected);
  if(!std::isfinite(error) || error>1.e-6f) {
    std::fprintf(stderr,"%s tangent normal at (%.3f,%.3f): (%.6f,%.6f), expected (%.1f,%.1f).\n",
        name,pixel.x,pixel.y,actual.x,actual.y,expected.x,expected.y);
    return false;
  }
  return true;
}

bool CheckSection(const char* name,float2 pixel,float2 across,float2 size,float radius,float2 normal) {
  bool good=true;
  for(float offset:{-1.f,0.f,1.f}) {
    if(!CheckNormal(name,pixel+across*offset,size,radius,normal)) good=false;
  }
  const auto before=orion::glass::GlassSample(pixel-across,size,radius);
  const auto tangent=orion::glass::GlassSample(pixel,size,radius);
  const auto after=orion::glass::GlassSample(pixel+across,size,radius);
  // Adjacent points are only .001px apart. The old exact-tangent bug caused
  // a multi-pixel sample jump at the centre despite continuous neighbours.
  const float jump=std::max(length(tangent-before),length(after-tangent));
  if(!std::isfinite(jump) || jump>.05f) {
    std::fprintf(stderr,"%s sample discontinuity at (%.3f,%.3f): %.6fpx.\n",name,pixel.x,pixel.y,jump);
    good=false;
  }
  return good;
}
}  // namespace

int main() {
  constexpr float radius=24.f,epsilon=.001f;
  const std::array<float2,2> sizes{{{820.f,523.f},{1280.f,800.f}}};
  bool good=true;
  int sections=0;
  for(const auto size:sizes) {
    // Cover each straight section away from the circular corners, including
    // both x=radius and y=height-radius lines that produced the visible box.
    for(float fraction:{.1f,.25f,.5f,.75f,.9f}) {
      const float x=radius+(size.x-2*radius)*fraction;
      const float y=radius+(size.y-2*radius)*fraction;
      if(!CheckSection("top",{x,radius},{0,epsilon},size,radius,{0,-1})) good=false;
      if(!CheckSection("bottom",{x,size.y-radius},{0,epsilon},size,radius,{0,1})) good=false;
      if(!CheckSection("left",{radius,y},{epsilon,0},size,radius,{-1,0})) good=false;
      if(!CheckSection("right",{size.x-radius,y},{epsilon,0},size,radius,{1,0})) good=false;
      sections+=4;
    }
  }
  if(good) std::printf("Glass optics passed: four axis-aligned tangent normals and .001px sample continuity across %d straight sections.\n",sections);
  return good?0:1;
}
