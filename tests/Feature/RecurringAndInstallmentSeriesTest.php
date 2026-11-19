<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Models\Account;
use App\Models\Category;
use App\Models\Installment;
use App\Models\RecurringTransaction;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Fase 1: saldo por data, recorrência com "último valor" e parcelamento a partir da parcela X.
 */
class RecurringAndInstallmentSeriesTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $account;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->user = User::factory()->create();
        $this->account = app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->category = Category::where('user_id', $this->user->id)->where('name', 'Alimentação')->firstOrFail();
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function store(array $overrides = []): void
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), [
                'description' => 'Conta',
                'amount' => 100,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->account->id,
                'date' => now()->toDateString(),
                'is_installment' => false,
                'installments_count' => 2,
                'installment_start' => 1,
                'amount_mode' => 'total',
                'is_recurring' => false,
                'frequency' => 'monthly',
                ...$overrides,
            ])
            ->assertSessionHasNoErrors();
    }

    private function balance(): float
    {
        return (float) $this->account->fresh()->balance;
    }

    private function processDue(): void
    {
        $this->artisan('phamani:process-due')->assertSuccessful();
    }

    public function test_future_transaction_only_hits_balance_when_paid(): void
    {
        $this->store(['type' => 'income', 'amount' => 3800, 'date' => '2026-12-04']);

        $this->assertEquals(0.0, $this->balance());
        $this->assertNull(Transaction::firstOrFail()->paid_at);

        // Chegou o dia, mas ninguém marcou como recebido: o saldo não muda.
        $this->travelTo('2026-12-04 00:30:00');
        $this->processDue();
        $this->assertEquals(0.0, $this->balance());

        $this->actingAs($this->user)->post(route('transactions.pay', Transaction::firstOrFail()))->assertRedirect();
        $this->processDue(); // rodar de novo não pode aplicar duas vezes

        $this->assertEquals(3800.0, $this->balance());
        $this->assertTrue(Transaction::firstOrFail()->balance_applied);
    }

    public function test_recurring_repeats_last_corrected_value(): void
    {
        $this->store(['description' => 'Juros Caixa', 'is_recurring' => true, 'amount' => 474.14, 'auto_pay' => true]);
        $first = Transaction::firstOrFail();

        // Correção do mês: o boleto veio maior.
        $this->actingAs($this->user)
            ->put(route('transactions.update', $first), [
                'description' => 'Juros Caixa',
                'amount' => 480.00,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->account->id,
                'date' => $first->date->toDateString(),
            ])
            ->assertSessionHasNoErrors();

        $this->travelTo('2026-12-18 01:00:00');
        $this->processDue();

        $occurrences = Transaction::orderBy('date')->get();

        $this->assertCount(2, $occurrences);
        $this->assertSame('2026-12-18', $occurrences[1]->date->toDateString());
        $this->assertEquals(480.00, (float) $occurrences[1]->amount);
        $this->assertEquals(-960.00, $this->balance());
        $this->assertSame('2027-01-18', RecurringTransaction::firstOrFail()->next_run->toDateString());
    }

    public function test_monthly_recurrence_does_not_drift_the_day(): void
    {
        $this->travelTo('2026-01-31 09:00:00');
        $this->store(['is_recurring' => true]);

        $this->travelTo('2026-03-31 09:00:00');
        $this->processDue();

        $this->assertSame(
            ['2026-01-31', '2026-02-28', '2026-03-31'],
            Transaction::orderBy('date')->get()->map(fn ($t) => $t->date->toDateString())->all(),
        );
    }

    public function test_recurring_with_past_start_is_backfilled_on_creation(): void
    {
        $this->store(['is_recurring' => true, 'date' => '2026-09-18']);

        $this->assertSame(3, Transaction::count()); // set, out, nov
        $this->assertEquals(-300.0, $this->balance());
    }

    public function test_ended_recurrence_stops_generating(): void
    {
        $this->store(['is_recurring' => true]);
        $recurring = RecurringTransaction::firstOrFail();

        $this->actingAs($this->user)
            ->post(route('recurring.end', $recurring))
            ->assertRedirect();

        $this->travelTo('2027-02-18 01:00:00');
        $this->processDue();

        $this->assertSame(1, Transaction::count());
    }

    public function test_cannot_end_another_users_recurrence(): void
    {
        $this->store(['is_recurring' => true]);
        $recurring = RecurringTransaction::firstOrFail();

        $this->actingAs(User::factory()->create())
            ->post(route('recurring.end', $recurring))
            ->assertNotFound();

        $this->assertNull($recurring->fresh()->end_date);
    }

    public function test_installment_can_start_from_a_given_parcel(): void
    {
        // Empréstimo Caixa já na 15/24, R$ 179,08 por parcela.
        $this->store([
            'description' => 'Empréstimo Caixa',
            'amount' => 179.08,
            'is_installment' => true,
            'installments_count' => 24,
            'installment_start' => 15,
            'amount_mode' => 'installment',
        ]);

        $parcels = Transaction::orderBy('installment_number')->get();

        $this->assertCount(10, $parcels);
        $this->assertSame(range(15, 24), $parcels->pluck('installment_number')->all());
        $this->assertSame('Empréstimo Caixa (15/24)', $parcels->first()->name);
        $this->assertTrue($parcels->every(fn ($p) => (float) $p->amount === 179.08));
        $this->assertSame('2027-08-18', $parcels->last()->date->toDateString());
        $this->assertEquals(-179.08, $this->balance());
        $this->assertEquals(179.08 * 24, (float) Installment::firstOrFail()->total_amount);
    }

    public function test_each_parcel_hits_balance_on_its_date(): void
    {
        $this->store(['amount' => 300, 'amount_mode' => 'total', 'is_installment' => true, 'installments_count' => 3, 'auto_pay' => true]);
        $this->assertEquals(-100.0, $this->balance());

        $this->travelTo('2026-12-18 00:30:00');
        $this->processDue();

        $this->assertEquals(-200.0, $this->balance());
    }

    public function test_parcel_correction_can_be_applied_to_following_parcels(): void
    {
        // Entrada MRV: corrige a parcela e repete nas próximas.
        $this->store([
            'description' => 'Entrada MRV',
            'amount' => 500,
            'is_installment' => true,
            'installments_count' => 3,
            'amount_mode' => 'installment',
        ]);
        $second = Transaction::where('installment_number', 2)->firstOrFail();

        $this->actingAs($this->user)
            ->put(route('transactions.update', $second), [
                'description' => 'Entrada MRV',
                'amount' => 504.78,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->account->id,
                'date' => $second->date->toDateString(),
                'apply_to_following' => true,
            ])
            ->assertSessionHasNoErrors();

        $this->assertSame(
            [500.0, 504.78, 504.78],
            Transaction::orderBy('installment_number')->get()->map(fn ($t) => (float) $t->amount)->all(),
        );
        // Só a 1ª parcela (hoje) está no saldo.
        $this->assertEquals(-500.0, $this->balance());
    }

    public function test_recent_shows_first_launched_parcel(): void
    {
        $this->store([
            'description' => 'Empréstimo Caixa',
            'amount' => 179.08,
            'is_installment' => true,
            'installments_count' => 24,
            'installment_start' => 15,
            'amount_mode' => 'installment',
        ]);

        $this->actingAs($this->user)
            ->get(route('dashboard'))
            ->assertInertia(fn ($page) => $page
                ->has('recentTransactions', 1)
                ->where('recentTransactions.0.name', 'Empréstimo Caixa (15/24)'));
    }

    public function test_total_mode_is_the_whole_purchase_even_when_starting_later(): void
    {
        // "Telefone de R$ 625 em 4x, já na 3ª": lança 3/4 e 4/4 de R$ 156,25.
        $this->store([
            'description' => 'Telefone',
            'amount' => 625,
            'is_installment' => true,
            'installments_count' => 4,
            'installment_start' => 3,
            'amount_mode' => 'total',
        ]);

        $parcels = Transaction::orderBy('installment_number')->get();

        $this->assertSame([3, 4], $parcels->pluck('installment_number')->all());
        $this->assertSame([156.25, 156.25], $parcels->map(fn ($p) => (float) $p->amount)->all());
        $this->assertEquals(625.0, (float) Installment::firstOrFail()->total_amount);
    }
}
