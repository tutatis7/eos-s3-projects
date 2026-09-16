/*==========================================================
 *
 *    File   : led_button.h
 *    Purpose: USR button + RGB LED color cycling task
 *
 *=========================================================*/

#ifndef LED_BUTTON_H
#define LED_BUTTON_H

#include <stdint.h>

/* Start the task that watches the USR button and cycles the LED color */
void led_button_task_start(void);

/* Set the LED to a color by name ("red", "cyan", "off", ...). Returns 0 if unknown. */
int led_set_color_by_name(const char *name);

/* Print the available color names over the debug/CLI port */
void led_print_colors(void);

/* Number of USR button presses since boot */
uint32_t led_button_press_count(void);

#endif /* LED_BUTTON_H */
