<?php

namespace Tests\Unit;

use App\Enums\RecurringFrequency;
use Carbon\CarbonImmutable;
use PHPUnit\Framework\TestCase;

class RecurringFrequencyTest extends TestCase
{
    public function test_next_occurrence_is_calculated_without_month_overflow(): void
    {
        $base = CarbonImmutable::parse('2026-01-31');

        $this->assertSame('2026-02-01', RecurringFrequency::DAILY->nextAfter($base)->toDateString());
        $this->assertSame('2026-02-07', RecurringFrequency::WEEKLY->nextAfter($base)->toDateString());
        $this->assertSame('2026-02-28', RecurringFrequency::MONTHLY->nextAfter($base)->toDateString());
        $this->assertSame('2027-01-31', RecurringFrequency::YEARLY->nextAfter($base)->toDateString());
    }

    public function test_labels_are_in_portuguese(): void
    {
        $this->assertSame('Mensal', RecurringFrequency::MONTHLY->label());
    }
}
