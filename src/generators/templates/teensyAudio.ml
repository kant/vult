(*
The MIT License (MIT)

Copyright (c) 2014 Leonardo Laguna Ruiz

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*)

(** Template for the Teensy Audio library *)


(** Header function *)
let header (module_name:string) (output:string) (code:Pla.t) : Pla.t =
   let file = String.uppercase output in
   {pla|
#ifndef <#file#s>_H
#define <#file#s>_H

#include <stdint.h>
#include <math.h>
#include "vultin.h"
#include "AudioStream.h"

<#code#>

class <#output#s> : public AudioStream
{
public:
  <#output#s>(void) : AudioStream(0,NULL)
  {
     data = <#module_name#s>_process_init();
  }

  void begin() {
    <#module_name#s>_default(data);
  }

  // Handles note on events
  void noteOn(int note, int velocity){
    // If the velocity is larger than zero, means that is turning on
    if(velocity) <#module_name#s>_noteOn(data, note, velocity);
    else         <#module_name#s>_noteOff(data, note);
  }

  // Handles note off events
  void noteOff(int note, int velocity) {
    <#module_name#s>_noteOff(data, note);

  }

  // Handles control change events
  void controlChange(int control, int value) {
    <#module_name#s>_controlChange(data, control, value);
  }

  virtual void update(void);

private:
  <#module_name#s>_process_type data;

};

#endif // <#file#s>_H
|pla}


(** Implementation function *)
let implementation (module_name:string) (output:string) (code:Pla.t) : Pla.t =
   {pla|
#include "<#output#s>.h"

<#code#>

void <#output#s>::update(void)
{
  audio_block_t *block;
  short *bp;

  block = allocate();
  if (block) {
    bp = block->data;
      for(int i = 0;i < AUDIO_BLOCK_SAMPLES;i++) {
        fix16_t v = <#module_name#s>_process(data,0);
        *bp++ = (int16_t)(v / 2);
      }

    transmit(block,0);
    release(block);
  }
}

|pla}

let get = header, implementation