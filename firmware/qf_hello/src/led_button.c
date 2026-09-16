/*==========================================================
 *
 *    File   : led_button.c
 *    Purpose: USR button + RGB LED color cycling task
 *
 *    A FreeRTOS task polls the USR button every 20 ms. Each press moves the
 *    RGB LED to the next color and prints a line over USB serial.
 *
 *=========================================================*/

#include "Fw_global_config.h"
#include <string.h>
#include "FreeRTOS.h"
#include "task.h"
#include "RtosTask.h"
#include "eoss3_hal_gpio.h"
#include "dbg_uart.h"
#include "led_button.h"

/* GPIO numbers, as configured in pincfg_table.c */
#define GPIO_USR_BUTTON   0   /* PAD 6,  reads 0 while pressed (pull-up) */
#define GPIO_LED_BLUE     4   /* PAD 18, 1 = on */
#define GPIO_LED_GREEN    5   /* PAD 21, 1 = on */
#define GPIO_LED_RED      6   /* PAD 22, 1 = on */

#define POLL_MS           20  /* also the debounce interval */

struct color {
    const char *name;
    uint8_t     red, green, blue;
};

static const struct color colors[] = {
    { "off",     0, 0, 0 },
    { "red",     1, 0, 0 },
    { "yellow",  1, 1, 0 },
    { "green",   0, 1, 0 },
    { "cyan",    0, 1, 1 },
    { "blue",    0, 0, 1 },
    { "magenta", 1, 0, 1 },
    { "white",   1, 1, 1 },
};

#define NUM_COLORS  (sizeof(colors) / sizeof(colors[0]))

static int      current_color = 0;
static uint32_t press_count   = 0;

static void led_set_color(int index)
{
    current_color = index;
    HAL_GPIO_Write(GPIO_LED_RED,   colors[index].red);
    HAL_GPIO_Write(GPIO_LED_GREEN, colors[index].green);
    HAL_GPIO_Write(GPIO_LED_BLUE,  colors[index].blue);
}

int led_set_color_by_name(const char *name)
{
    for (int i = 0; i < (int)NUM_COLORS; i++) {
        if (strcmp(name, colors[i].name) == 0) {
            led_set_color(i);
            return 1;
        }
    }
    return 0;
}

void led_print_colors(void)
{
    for (int i = 0; i < (int)NUM_COLORS; i++) {
        dbg_str("  ");
        dbg_str(colors[i].name);
        dbg_str(i == current_color ? "  <- current\n" : "\n");
    }
}

uint32_t led_button_press_count(void)
{
    return press_count;
}

static int button_is_down(void)
{
    uint8_t level = 1;
    HAL_GPIO_Read(GPIO_USR_BUTTON, &level);
    return level == 0;
}

static void led_button_task(void *pvParameters)
{
    (void)pvParameters;

    int stable_down = button_is_down();
    int last_sample = stable_down;

    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(POLL_MS));

        /* Debounce: accept a new level only after two samples 20 ms apart agree */
        int sample = button_is_down();
        if (sample == last_sample && sample != stable_down) {
            stable_down = sample;
            if (stable_down) {
                press_count++;
                led_set_color((current_color + 1) % NUM_COLORS);
                dbg_str("USR button press #");
                dbg_int((int)press_count);
                dbg_str(" -> LED ");
                dbg_str(colors[current_color].name);
                dbg_str("\n");
            }
        }
        last_sample = sample;
    }
}

void led_button_task_start(void)
{
    led_set_color(0);
    xTaskCreate(led_button_task, "led_button", 512, NULL, PRIORITY_NORMAL, NULL);
}
