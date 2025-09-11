#ifndef _CGRA_FUNCTION_H_
#define _CGRA_FUNCTION_H_

#include <stdio.h>

void conv_check ( int32_t * Out_Img ) {
      
      int res[] = { 36, 42, 60, 90, 108, 126, 144 };
      
      for (int i=0; i<7; i++) {
          Out_Img[i] = res[i];
      }

      return;
}

#endif // _CGRA_FUNCTION_H_