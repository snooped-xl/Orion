#include "rain_effect.h"

#include <epoxy/gl.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace {
// Water-normal/thickness refraction model adapted from Lucas Bebber's Codrops
// RainEffect (2015), integrated into Orion's live Flutter/native-editor surface.
// https://github.com/codrops/RainEffect/blob/master/src/shaders/water.frag
// https://tympanus.net/codrops/licensing/ (MIT; attribution shipped in assets).
// The UI itself remains live below this layer: only wet pixels sample a texture.
constexpr const char* kVertex = R"GLSL(
#version 330 core
layout(location=0) in vec2 corner;
layout(location=1) in vec4 dropShape;
layout(location=2) in vec4 dropProperties;
uniform vec2 resolution;
uniform vec2 packetSize;
out vec2 pixel;
flat out vec4 shape;
flat out vec4 properties;
void main(){
  vec2 scale=resolution/max(packetSize,vec2(1));
  shape=vec4(dropShape.xy*scale,dropShape.zw*scale);
  properties=dropProperties;
  properties.w*=scale.y;
  float tail=properties.y>.5?properties.w:0.;
  vec2 from=shape.xy-vec2(shape.z*1.25+3.,shape.w+tail+3.);
  vec2 to=shape.xy+vec2(shape.z*1.25+3.,shape.w+3.);
  pixel=mix(from,to,corner);
  gl_Position=vec4(pixel.x/resolution.x*2.-1.,1.-pixel.y/resolution.y*2.,0,1);
}
)GLSL";
constexpr const char* kFragment = R"GLSL(
#version 330 core
in vec2 pixel;
flat in vec4 shape;
flat in vec4 properties;
uniform sampler2D frameImage;
uniform sampler2D editorImage;
uniform vec2 resolution;
uniform vec4 editorBounds;
uniform bool hasEditor;
uniform float cornerRadius;
out vec4 fragColor;
vec4 scene(vec2 p){
  vec4 bg=texture(frameImage,clamp(p/resolution,vec2(0),vec2(1)));
  vec3 rgb=bg.rgb*bg.a;
  if(hasEditor && all(greaterThanEqual(p,editorBounds.xy)) &&
      all(lessThan(p,editorBounds.xy+editorBounds.zw))){
    vec4 ed=texture(editorImage,clamp((p-editorBounds.xy)/editorBounds.zw,vec2(0),vec2(1)));
    rgb=ed.rgb*ed.a+rgb*(1.-ed.a);
    bg.a=ed.a+bg.a*(1.-ed.a);
  }
  return vec4(bg.a>.0001?rgb/bg.a:vec3(0),bg.a);
}
void main(){
  vec2 corner=max(abs(pixel-resolution*.5)-(resolution*.5-cornerRadius),vec2(0));
  float rounded=length(corner)-cornerRadius;
  if(rounded>.75)discard;
  vec2 q=(pixel-shape.xy)/max(shape.zw,vec2(.25));
  float pear=1.+.10*clamp(q.y,-1.,1.);
  q.x/=pear;
  float radius=length(q);
  float aa=max(fwidth(radius),.018);
  float body=1.-smoothstep(1.-aa,1.+aa,radius);
  float thickness=sqrt(max(0.,1.-dot(q,q)));
  // Codrops: refraction = waterNormal * (minRefraction + thickness * delta).
  // An inward ellipsoid normal magnifies text while the outer meniscus bends it.
  float lensRadius=max(shape.z,shape.w);
  float reach=clamp(lensRadius*.48,.65,3.5);
  vec2 normal=-q*vec2(.96,.78);
  vec2 offset=normal*(reach+thickness*min(lensRadius*.18,1.2));
  float trail=0.;
  vec2 trailOffset=vec2(0);
  if(properties.y>.5 && properties.w>.5){
    float behind=shape.y-pixel.y;
    float along=(behind-shape.w*.42)/max(properties.w,1.);
    float width=mix(max(.65,shape.z*.18),.35,clamp(along,0.,1.));
    float center=shape.x+sin(behind*.075+properties.z)*.24;
    float lateral=(pixel.x-center)/width;
    float sides=1.-smoothstep(.35,1.,abs(lateral));
    float ends=smoothstep(0.,.10,along)*(1.-smoothstep(.72,1.,along));
    trail=sides*ends*.18;
    trailOffset=vec2(-lateral*(.65+properties.x*.75),sin(behind*.07+properties.z)*.25);
  }
  float coverage=max(body*(.50+properties.x*.20),trail);
  if(coverage<.006)discard;
  if(body<.02)offset=trailOffset;
  else offset=mix(trailOffset,offset,body);
  // Small chromatic dispersion follows the water normal, not a colored sprite.
  vec4 middle=scene(pixel+offset);
  vec3 refracted=vec3(scene(pixel+offset*1.008).r,middle.g,scene(pixel+offset*.992).b);
  // A narrow, antialiased wet crescent stays visible on dark UI without
  // increasing lens coverage or the displacement underneath the droplet.
  float rimWidth=max(.065,fwidth(radius)*.65);
  float rim=exp(-pow((radius-.86)/rimWidth,2.))*body;
  vec2 light=normalize(vec2(-.55,-.83));
  float shine=max(0.,dot(q,light))*rim*.22;
  float glint=exp(-dot((q-vec2(-.31,-.48))*vec2(5.5,7.),
                       (q-vec2(-.31,-.48))*vec2(5.5,7.)))*.09*body;
  float shadow=max(0.,dot(q,-light))*rim*.085;
  refracted=clamp(refracted*(1.-shadow)+shine+glint,0.,1.);
  float alpha=coverage*middle.a*(1.-smoothstep(-.5,.75,rounded));
  fragColor=vec4(refracted*alpha,alpha);
}
)GLSL";
struct RainEffect {
  GtkWindow* window=nullptr;
  GtkOverlay* overlay=nullptr;
  GtkWidget* canvas=nullptr;
  FlMethodChannel* channel=nullptr;
  GdkPixbuf* frame=nullptr;
  GdkPixbuf* editor=nullptr;
  GdkRectangle editor_bounds{0,0,0,0};
  bool enabled=false, reduced_motion=false, destroyed=false;
  bool texture_dirty[2]={true,true}, drops_dirty=true;
  std::vector<uint8_t> png_bytes[2];
  double opacity=1, corner_radius=16;
  double packet_width=1, packet_height=1;
  std::vector<float> drops;
  GLuint program=0, vao=0, quad_buffer=0, drop_buffer=0;
  GLuint textures[2]={0,0};
  int texture_widths[2]={0,0}, texture_heights[2]={0,0};
  std::string error;
};
double number(FlValue* value,double fallback){
  if(value==nullptr)return fallback;
  double n=fallback;
  if(fl_value_get_type(value)==FL_VALUE_TYPE_FLOAT)n=fl_value_get_float(value);
  if(fl_value_get_type(value)==FL_VALUE_TYPE_INT)n=fl_value_get_int(value);
  return std::isfinite(n)?n:fallback;
}
bool boolean(FlValue* value){return value!=nullptr&&fl_value_get_type(value)==FL_VALUE_TYPE_BOOL&&fl_value_get_bool(value);}

GdkPixbuf* decode_png(FlValue* value){
  if(value==nullptr||fl_value_get_type(value)!=FL_VALUE_TYPE_UINT8_LIST)return nullptr;
  const size_t size=fl_value_get_length(value);
  const uint8_t* bytes=fl_value_get_uint8_list(value);
  static constexpr uint8_t signature[]={137,80,78,71,13,10,26,10};
  if(size<24||size>8*1024*1024||std::memcmp(bytes,signature,8)!=0)return nullptr;
  auto integer=[&](int i){return(uint32_t(bytes[i])<<24)|(uint32_t(bytes[i+1])<<16)|(uint32_t(bytes[i+2])<<8)|bytes[i+3];};
  const uint32_t w=integer(16),h=integer(20);
  if(w<1||h<1||w>4096||h>4096||uint64_t(w)*h>8*1024*1024)return nullptr;
  g_autoptr(GError) error=nullptr;
  g_autoptr(GdkPixbufLoader) loader=gdk_pixbuf_loader_new_with_type("png",&error);
  if(loader==nullptr||!gdk_pixbuf_loader_write(loader,bytes,size,&error)||!gdk_pixbuf_loader_close(loader,&error))return nullptr;
  GdkPixbuf* image=gdk_pixbuf_loader_get_pixbuf(loader);
  if(image==nullptr)return nullptr;
  if(!gdk_pixbuf_get_has_alpha(image))return gdk_pixbuf_add_alpha(image,FALSE,0,0,0);
  return GDK_PIXBUF(g_object_ref(image));
}
// The Flutter and WebKit images update independently. Retain an exact copy of
// each accepted PNG so unchanged samples need neither decoding nor GPU upload.
// Invalid optional editor frames still remove that editor, as before.
bool update_image(RainEffect* host,int index,FlValue* value){
  GdkPixbuf** target=index==0?&host->frame:&host->editor;
  auto& previous=host->png_bytes[index];
  if(*target!=nullptr&&!previous.empty()&&value!=nullptr&&
      fl_value_get_type(value)==FL_VALUE_TYPE_UINT8_LIST&&
      previous.size()==fl_value_get_length(value)&&
      std::memcmp(previous.data(),fl_value_get_uint8_list(value),previous.size())==0){
    return true;
  }
  GdkPixbuf* image=decode_png(value);
  if(image==nullptr&&index==0)return false;
  if(image!=nullptr){
    const uint8_t* bytes=fl_value_get_uint8_list(value);
    previous.assign(bytes,bytes+fl_value_get_length(value));
    host->texture_dirty[index]=true;
  }else{
    previous.clear();
    if(*target!=nullptr)host->texture_dirty[index]=true;
  }
  g_set_object(target,image);g_clear_object(&image);
  return true;
}
void pass_through(GtkWidget* canvas){
  if(!gtk_widget_get_realized(canvas))return;
  GdkWindow* window=gtk_widget_get_window(canvas);
  GtkWidget* parent=gtk_widget_get_parent(canvas);
  // GLArea is a no-window widget, but GtkOverlay gives it a separate GdkWindow
  // wrapper. Make that wrapper transparent to picking without touching the
  // shared parent window used by Flutter and other controls.
  if(window==nullptr||(!gtk_widget_get_has_window(canvas)&&parent!=nullptr&&
      window==gtk_widget_get_window(parent)))return;
  gdk_window_set_pass_through(window,TRUE);
  cairo_region_t* empty=cairo_region_create();
  if(gtk_widget_get_has_window(canvas))gtk_widget_input_shape_combine_region(canvas,empty);
  gdk_window_input_shape_combine_region(window,empty,0,0);
  cairo_region_destroy(empty);
}
GLuint compile(GLenum type,const char* source,std::string& error){
  const GLuint shader=glCreateShader(type);
  glShaderSource(shader,1,&source,nullptr);glCompileShader(shader);
  GLint ok=0;glGetShaderiv(shader,GL_COMPILE_STATUS,&ok);
  if(!ok){GLchar log[4096]{};glGetShaderInfoLog(shader,sizeof(log),nullptr,log);error=log;glDeleteShader(shader);return 0;}
  return shader;
}
void release_gl(RainEffect* host){
  if(host->program)glDeleteProgram(host->program);
  if(host->quad_buffer)glDeleteBuffers(1,&host->quad_buffer);
  if(host->drop_buffer)glDeleteBuffers(1,&host->drop_buffer);
  if(host->vao)glDeleteVertexArrays(1,&host->vao);
  glDeleteTextures(2,host->textures);
  host->program=host->quad_buffer=host->drop_buffer=host->vao=0;
  host->textures[0]=host->textures[1]=0;
  host->texture_widths[0]=host->texture_widths[1]=host->texture_heights[0]=host->texture_heights[1]=0;
  host->texture_dirty[0]=host->texture_dirty[1]=true;
}
bool initialize_gl(RainEffect* host){
  host->error.clear();
  const GLuint vertex=compile(GL_VERTEX_SHADER,kVertex,host->error);
  if(!vertex)return false;
  const GLuint fragment=compile(GL_FRAGMENT_SHADER,kFragment,host->error);
  if(!fragment){glDeleteShader(vertex);return false;}
  host->program=glCreateProgram();glAttachShader(host->program,vertex);glAttachShader(host->program,fragment);glLinkProgram(host->program);
  glDeleteShader(vertex);glDeleteShader(fragment);
  GLint ok=0;glGetProgramiv(host->program,GL_LINK_STATUS,&ok);
  if(!ok){GLchar log[4096]{};glGetProgramInfoLog(host->program,sizeof(log),nullptr,log);host->error=log;release_gl(host);return false;}
  const float quad[]={0,0,1,0,0,1,1,1};
  glGenVertexArrays(1,&host->vao);glBindVertexArray(host->vao);
  glGenBuffers(1,&host->quad_buffer);glBindBuffer(GL_ARRAY_BUFFER,host->quad_buffer);glBufferData(GL_ARRAY_BUFFER,sizeof(quad),quad,GL_STATIC_DRAW);
  glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,2*sizeof(float),nullptr);glEnableVertexAttribArray(0);
  glGenBuffers(1,&host->drop_buffer);glBindBuffer(GL_ARRAY_BUFFER,host->drop_buffer);
  glVertexAttribPointer(1,4,GL_FLOAT,GL_FALSE,8*sizeof(float),nullptr);glEnableVertexAttribArray(1);glVertexAttribDivisor(1,1);
  glVertexAttribPointer(2,4,GL_FLOAT,GL_FALSE,8*sizeof(float),reinterpret_cast<void*>(4*sizeof(float)));glEnableVertexAttribArray(2);glVertexAttribDivisor(2,1);
  glGenTextures(2,host->textures);
  for(int i=0;i<2;i++){glBindTexture(GL_TEXTURE_2D,host->textures[i]);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);}
  glBindVertexArray(0);host->texture_dirty[0]=host->texture_dirty[1]=host->drops_dirty=true;return true;
}
void upload_image(RainEffect* host,int index,GdkPixbuf* image){
  glActiveTexture(GL_TEXTURE0+index);glBindTexture(GL_TEXTURE_2D,host->textures[index]);
  const uint8_t empty[]={0,0,0,0};
  const int w=image?gdk_pixbuf_get_width(image):1,h=image?gdk_pixbuf_get_height(image):1;
  const void* pixels=image?gdk_pixbuf_read_pixels(image):empty;
  glPixelStorei(GL_UNPACK_ALIGNMENT,1);
  if(host->texture_widths[index]==w&&host->texture_heights[index]==h){
    glTexSubImage2D(GL_TEXTURE_2D,0,0,0,w,h,GL_RGBA,GL_UNSIGNED_BYTE,pixels);
  }else{
    glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,w,h,0,GL_RGBA,GL_UNSIGNED_BYTE,pixels);
    host->texture_widths[index]=w;host->texture_heights[index]=h;
  }
  glPixelStorei(GL_UNPACK_ALIGNMENT,4);
}
bool render_gl(RainEffect* host,int width,int height){
  glClearColor(0,0,0,0);glClear(GL_COLOR_BUFFER_BIT);
  if(!host->enabled||host->frame==nullptr||host->drops.empty()||width<1||height<1)return true;
  if(!host->program&&!initialize_gl(host))return false;
  for(int i=0;i<2;i++)if(host->texture_dirty[i]){
    upload_image(host,i,i==0?host->frame:host->editor);host->texture_dirty[i]=false;
  }
  glUseProgram(host->program);glBindVertexArray(host->vao);
  if(host->drops_dirty){glBindBuffer(GL_ARRAY_BUFFER,host->drop_buffer);glBufferData(GL_ARRAY_BUFFER,host->drops.size()*sizeof(float),host->drops.data(),GL_DYNAMIC_DRAW);host->drops_dirty=false;}
  glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D,host->textures[0]);
  glActiveTexture(GL_TEXTURE1);glBindTexture(GL_TEXTURE_2D,host->textures[1]);
  glUniform1i(glGetUniformLocation(host->program,"frameImage"),0);glUniform1i(glGetUniformLocation(host->program,"editorImage"),1);
  glUniform2f(glGetUniformLocation(host->program,"resolution"),width,height);
  glUniform2f(glGetUniformLocation(host->program,"packetSize"),host->packet_width,host->packet_height);
  const auto& b=host->editor_bounds;
  glUniform4f(glGetUniformLocation(host->program,"editorBounds"),b.x,b.y,b.width,b.height);
  glUniform1i(glGetUniformLocation(host->program,"hasEditor"),host->editor!=nullptr&&b.width>0&&b.height>0);
  glUniform1f(glGetUniformLocation(host->program,"cornerRadius"),host->corner_radius);
  glEnable(GL_BLEND);glBlendFunc(GL_ONE,GL_ONE_MINUS_SRC_ALPHA);glDisable(GL_DEPTH_TEST);
  glDrawArraysInstanced(GL_TRIANGLE_STRIP,0,4,host->drops.size()/8);
  glDisable(GL_BLEND);glBindVertexArray(0);glUseProgram(0);glActiveTexture(GL_TEXTURE0);
  return glGetError()==GL_NO_ERROR;
}
void queue(RainEffect* host){
  if(host->enabled&&host->canvas!=nullptr&&!host->destroyed){
    gtk_overlay_reorder_overlay(host->overlay,host->canvas,-1);
    gtk_gl_area_queue_render(GTK_GL_AREA(host->canvas));
  }
}
void configure(RainEffect* host,bool enabled,bool reduced,double opacity,double radius){
  host->enabled=enabled;host->reduced_motion=reduced;host->opacity=opacity;host->corner_radius=radius;
  gtk_widget_set_opacity(GTK_WIDGET(host->window),opacity);
  if(enabled){gtk_widget_show(host->canvas);pass_through(host->canvas);queue(host);}
  else{
    gtk_widget_hide(host->canvas);g_clear_object(&host->frame);g_clear_object(&host->editor);host->drops.clear();
    for(int i=0;i<2;i++)std::vector<uint8_t>{}.swap(host->png_bytes[i]);
    host->texture_dirty[0]=host->texture_dirty[1]=host->drops_dirty=true;
  }
}
void method_call(FlMethodChannel*,FlMethodCall* call,gpointer data){
  auto* host=static_cast<RainEffect*>(data);
  FlValue* args=fl_method_call_get_args(call);
  if(host->destroyed||args==nullptr||fl_value_get_type(args)!=FL_VALUE_TYPE_MAP){fl_method_call_respond_error(call,"invalid_arguments","Expected rain configuration.",nullptr,nullptr);return;}
  const char* method=fl_method_call_get_name(call);
  if(std::strcmp(method,"configure")!=0&&!host->error.empty()){
    fl_method_call_respond_error(call,"rain_shader_unavailable",host->error.c_str(),nullptr,nullptr);return;
  }
  if(std::strcmp(method,"configure")==0){
    configure(host,boolean(fl_value_lookup_string(args,"enabled")),boolean(fl_value_lookup_string(args,"reducedMotion")),std::clamp(number(fl_value_lookup_string(args,"opacity"),.9),0.0,1.0),std::clamp(number(fl_value_lookup_string(args,"cornerRadius"),16),0.0,64.0));
    const GError* context_error=gtk_gl_area_get_error(GTK_GL_AREA(host->canvas));
    if(host->enabled&&(context_error!=nullptr||!host->error.empty())){
      gtk_widget_hide(host->canvas);
      fl_method_call_respond_error(call,"rain_shader_unavailable",context_error?context_error->message:host->error.c_str(),nullptr,nullptr);return;
    }
    g_autoptr(FlValue) result=fl_value_new_map();fl_value_set_string_take(result,"nativeRain",fl_value_new_bool(true));fl_value_set_string_take(result,"backend",fl_value_new_string("OpenGL"));fl_value_set_string_take(result,"opacity",fl_value_new_float(host->opacity));fl_method_call_respond_success(call,result,nullptr);return;
  }
  if(std::strcmp(method,"frame")==0){
    if(!host->enabled){fl_method_call_respond_success(call,nullptr,nullptr);return;}
    if(!update_image(host,0,fl_value_lookup_string(args,"png"))){fl_method_call_respond_error(call,"invalid_frame","Expected a bounded PNG frame.",nullptr,nullptr);return;}
    update_image(host,1,fl_value_lookup_string(args,"editorPng"));
    host->editor_bounds={
      static_cast<int>(std::floor(std::clamp(number(fl_value_lookup_string(args,"editorX"),0),-16384.0,16384.0))),
      static_cast<int>(std::floor(std::clamp(number(fl_value_lookup_string(args,"editorY"),0),-16384.0,16384.0))),
      static_cast<int>(std::ceil(std::clamp(number(fl_value_lookup_string(args,"editorWidth"),0),0.0,16384.0))),
      static_cast<int>(std::ceil(std::clamp(number(fl_value_lookup_string(args,"editorHeight"),0),0.0,16384.0)))};
    queue(host);fl_method_call_respond_success(call,nullptr,nullptr);return;
  }
  if(std::strcmp(method,"drops")==0){
    if(!host->enabled){fl_method_call_respond_success(call,nullptr,nullptr);return;}
    FlValue* value=fl_value_lookup_string(args,"data");
    if(value==nullptr||fl_value_get_type(value)!=FL_VALUE_TYPE_FLOAT32_LIST||fl_value_get_length(value)%8!=0||fl_value_get_length(value)>2048*8){fl_method_call_respond_error(call,"invalid_drops","Expected bounded eight-float droplet rows.",nullptr,nullptr);return;}
    const float* input=fl_value_get_float32_list(value);const size_t count=fl_value_get_length(value);
    for(size_t i=0;i<count;i++){if(!std::isfinite(input[i])){fl_method_call_respond_error(call,"invalid_drops","Droplet values must be finite.",nullptr,nullptr);return;}}
    host->drops.assign(input,input+count);
    for(size_t i=0;i<count;i+=8){host->drops[i]=std::clamp(host->drops[i],-65536.f,65536.f);host->drops[i+1]=std::clamp(host->drops[i+1],-65536.f,65536.f);host->drops[i+2]=std::clamp(host->drops[i+2],.25f,256.f);host->drops[i+3]=std::clamp(host->drops[i+3],.25f,512.f);host->drops[i+4]=std::clamp(host->drops[i+4],0.f,1.f);host->drops[i+5]=host->drops[i+5]>.5f?1:0;host->drops[i+7]=std::clamp(host->drops[i+7],0.f,2048.f);}
    host->packet_width=std::clamp(number(fl_value_lookup_string(args,"width"),1),1.0,16384.0);host->packet_height=std::clamp(number(fl_value_lookup_string(args,"height"),1),1.0,16384.0);
    host->drops_dirty=true;queue(host);fl_method_call_respond_success(call,nullptr,nullptr);return;
  }
  fl_method_call_respond_not_implemented(call,nullptr);
}
void disconnect_channel(RainEffect* host){if(host->channel==nullptr)return;fl_method_channel_set_method_call_handler(host->channel,nullptr,nullptr,nullptr);g_clear_object(&host->channel);}
void release(gpointer data){auto* host=static_cast<RainEffect*>(data);disconnect_channel(host);g_clear_object(&host->frame);g_clear_object(&host->editor);delete host;}
}  // namespace

void rain_effect_attach(GtkWindow* window,FlView* view,GtkOverlay* overlay){
  auto* host=new RainEffect();host->window=window;host->overlay=overlay;
  host->canvas=gtk_gl_area_new();gtk_gl_area_set_required_version(GTK_GL_AREA(host->canvas),3,3);gtk_gl_area_set_use_es(GTK_GL_AREA(host->canvas),FALSE);gtk_gl_area_set_has_alpha(GTK_GL_AREA(host->canvas),TRUE);gtk_gl_area_set_auto_render(GTK_GL_AREA(host->canvas),FALSE);
  gtk_widget_set_halign(host->canvas,GTK_ALIGN_FILL);gtk_widget_set_valign(host->canvas,GTK_ALIGN_FILL);gtk_widget_set_hexpand(host->canvas,TRUE);gtk_widget_set_vexpand(host->canvas,TRUE);gtk_widget_set_can_focus(host->canvas,FALSE);gtk_widget_set_sensitive(host->canvas,FALSE);gtk_widget_set_no_show_all(host->canvas,TRUE);
  gtk_overlay_add_overlay(overlay,host->canvas);gtk_overlay_set_overlay_pass_through(overlay,host->canvas,TRUE);
  g_signal_connect(host->canvas,"realize",G_CALLBACK(+[](GtkWidget* widget,gpointer data){auto* effect=static_cast<RainEffect*>(data);pass_through(widget);gtk_gl_area_make_current(GTK_GL_AREA(widget));if(gtk_gl_area_get_error(GTK_GL_AREA(widget))==nullptr&&!initialize_gl(effect)){g_warning("Orion rain shader: %s",effect->error.c_str());}}),host);
  g_signal_connect(host->canvas,"render",G_CALLBACK(+[](GtkGLArea* area,GdkGLContext*,gpointer data)->gboolean{
    auto* effect=static_cast<RainEffect*>(data);
    if(!render_gl(effect,gtk_widget_get_allocated_width(GTK_WIDGET(area)),gtk_widget_get_allocated_height(GTK_WIDGET(area)))){
      if(effect->error.empty())effect->error="The OpenGL rain pass could not render.";
      g_warning("Orion rain shader: %s",effect->error.c_str());
      effect->enabled=false;
      // Return from GTK's current render before hiding its optional GL layer.
      g_idle_add_full(G_PRIORITY_DEFAULT_IDLE,+[](gpointer widget)->gboolean{
        gtk_widget_hide(GTK_WIDGET(widget));return G_SOURCE_REMOVE;
      },g_object_ref(area),g_object_unref);
    }
    return TRUE;
  }),host);
  g_signal_connect(host->canvas,"unrealize",G_CALLBACK(+[](GtkWidget* widget,gpointer data){auto* effect=static_cast<RainEffect*>(data);gtk_gl_area_make_current(GTK_GL_AREA(widget));if(gtk_gl_area_get_error(GTK_GL_AREA(widget))==nullptr)release_gl(effect);}),host);
  g_signal_connect(host->canvas,"destroy",G_CALLBACK(+[](GtkWidget*,gpointer data){auto* effect=static_cast<RainEffect*>(data);effect->canvas=nullptr;effect->destroyed=true;}),host);
  g_autoptr(FlStandardMethodCodec) codec=fl_standard_method_codec_new();host->channel=fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)),"orion/rain",FL_METHOD_CODEC(codec));fl_method_channel_set_method_call_handler(host->channel,method_call,host,nullptr);g_object_set_data_full(G_OBJECT(window),"orion-rain-effect",host,release);
  // Unregister while this window's engine is still alive. Window finalization
  // can follow its child renderer/engine teardown by several platform tasks.
  g_signal_connect(window,"destroy",G_CALLBACK(+[](GtkWidget*,gpointer data){disconnect_channel(static_cast<RainEffect*>(data));}),host);
}
