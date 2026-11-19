#include "includes.h"
#include "fw_status.h"

void fw_status_clear(void)
{
    REG_FW_STATUS = 0;
    REG_FW_REPORT = 0;
}

void fw_status_report(uint32_t value)
{
    REG_FW_REPORT = value;
}

void fw_status_end(int ok)
{
    REG_FW_STATUS = ok ? FW_STATUS_PASS : FW_STATUS_FAIL;
}
