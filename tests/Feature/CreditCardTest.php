<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\ICreditCardService;
use App\Models\Account;
use App\Models\Category;
use App\Models\CreditCardInvoice;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

/**
 * Fase 2: cartão de crédito com limite e fatura.
 */
class CreditCardTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $checking;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->user = User::factory()->create();
        app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->category = Category::where('user_id', $this->user->id)->where('name', 'Transporte')->firstOrFail();

        $this->checking = Account::create([
            'user_id' => $this->user->id,
            'name' => 'Bradesco',
            'type' => 'checking',
            'balance' => 5000,
        ]);
    }

    private function createCard(int $closingDay = 25, int $dueDay = 5, float $limit = 5000): Account
    {
        $this->actingAs($this->user)
            ->post(route('accounts.store'), [
                'name' => 'Nubank',
                'type' => 'credit',
                'credit_limit' => $limit,
                'closing_day' => $closingDay,
                'due_day' => $dueDay,
                'payment_account_id' => $this->checking->id,
            ])
            ->assertSessionHasNoErrors();

        return Account::where('type', 'credit')->firstOrFail();
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function purchase(Account $card, array $overrides = []): void
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), [
                'description' => 'Uber',
                'amount' => 333.75,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $card->id,
                'date' => '2026-11-18',
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

    private function summary(Account $card): array
    {
        return app(ICreditCardService::class)->summary($card->fresh());
    }

    public function test_card_requires_limit_and_days(): void
    {
        $this->actingAs($this->user)
            ->post(route('accounts.store'), ['name' => 'Nubank', 'type' => 'credit'])
            ->assertSessionHasErrors(['credit_limit', 'closing_day', 'due_day']);
    }

    public function test_purchase_goes_to_invoice_and_does_not_touch_balances(): void
    {
        $card = $this->createCard();
        $this->purchase($card);

        $transaction = Transaction::firstOrFail();
        $invoice = CreditCardInvoice::firstOrFail();

        $this->assertSame($invoice->id, $transaction->invoice_id);
        $this->assertSame('2026-12-01', $invoice->reference_month->toDateString());
        $this->assertSame('2026-11-25', $invoice->closing_date->toDateString());
        $this->assertSame('2026-12-05', $invoice->due_date->toDateString());

        $this->assertEquals(0.0, (float) $card->fresh()->balance);
        $this->assertEquals(5000.0, (float) $this->checking->fresh()->balance);
        $this->assertFalse($transaction->fresh()->balance_applied);

        $summary = $this->summary($card);
        $this->assertEquals(333.75, $summary['used']);
        $this->assertEquals(4666.25, $summary['available']);
        $this->assertEquals(333.75, $summary['current_invoice']['total']);
    }

    public function test_purchase_after_closing_goes_to_next_invoice(): void
    {
        $card = $this->createCard();
        $this->purchase($card, ['date' => '2026-11-26']);

        $invoice = CreditCardInvoice::firstOrFail();
        $this->assertSame('2027-01-01', $invoice->reference_month->toDateString());
        $this->assertSame('2026-12-25', $invoice->closing_date->toDateString());
        $this->assertSame('2027-01-05', $invoice->due_date->toDateString());
    }

    public function test_due_day_after_closing_day_is_in_the_same_month(): void
    {
        $card = $this->createCard(closingDay: 5, dueDay: 15);
        $this->purchase($card);

        $invoice = CreditCardInvoice::firstOrFail();
        $this->assertSame('2026-12-05', $invoice->closing_date->toDateString());
        $this->assertSame('2026-12-15', $invoice->due_date->toDateString());
    }

    public function test_installments_consume_full_limit_and_spread_over_invoices(): void
    {
        $card = $this->createCard();
        $this->purchase($card, ['amount' => 1200, 'is_installment' => true, 'installments_count' => 3]);

        $this->assertSame(
            ['2026-12-01', '2027-01-01', '2027-02-01'],
            CreditCardInvoice::orderBy('reference_month')->get()->map(fn ($i) => $i->reference_month->toDateString())->all(),
        );

        $summary = $this->summary($card);
        $this->assertEquals(1200.0, $summary['used']);
        $this->assertEquals(3800.0, $summary['available']);
        $this->assertEquals(400.0, $summary['current_invoice']['total']);
    }

    public function test_paying_invoice_moves_money_without_counting_as_expense(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $invoice = CreditCardInvoice::firstOrFail();

        $this->actingAs($this->user)
            ->post(route('invoices.pay', $invoice), ['account_id' => $this->checking->id, 'date' => '2026-11-18'])
            ->assertSessionHasNoErrors()
            ->assertRedirect();

        $this->assertEquals(4666.25, (float) $this->checking->fresh()->balance);
        $this->assertSame('2026-11-18', $invoice->fresh()->paid_at->toDateString());
        $this->assertEquals(5000.0, $this->summary($card)['available']);

        // A despesa do mês continua sendo a compra (333,75), não compra + pagamento.
        // Fatura paga em 18/11: o dinheiro saiu em novembro, então a compra conta em novembro.
        $this->actingAs($this->user)
            ->get(route('dashboard'))
            ->assertInertia(fn (Assert $page) => $page
                ->where('kpis.expense.value', 333.75)
                ->where('kpis.total_balance', 4666.25)
                ->where('kpis.open_invoices', fn ($v) => (float) $v === 0.0));
    }

    public function test_undo_payment_restores_balance(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $invoice = CreditCardInvoice::firstOrFail();

        $this->actingAs($this->user)
            ->post(route('invoices.pay', $invoice), ['account_id' => $this->checking->id, 'date' => '2026-11-18']);

        $this->actingAs($this->user)
            ->delete(route('invoices.undo', $invoice))
            ->assertRedirect();

        $this->assertEquals(5000.0, (float) $this->checking->fresh()->balance);
        $this->assertNull($invoice->fresh()->paid_at);
    }

    public function test_cannot_pay_with_a_card_or_in_the_future(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $invoice = CreditCardInvoice::firstOrFail();

        $this->actingAs($this->user)
            ->post(route('invoices.pay', $invoice), ['account_id' => $card->id, 'date' => '2026-11-18'])
            ->assertSessionHasErrors('account_id');

        $this->actingAs($this->user)
            ->post(route('invoices.pay', $invoice), ['account_id' => $this->checking->id, 'date' => '2026-12-01'])
            ->assertSessionHasErrors('date');

        $this->assertNull($invoice->fresh()->paid_at);
    }

    public function test_other_users_cannot_see_or_pay_the_card(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $invoice = CreditCardInvoice::firstOrFail();
        $intruder = User::factory()->create();

        $this->actingAs($intruder)->get(route('cards.show', $card))->assertNotFound();
        $this->actingAs($intruder)
            ->post(route('invoices.pay', $invoice), ['account_id' => $this->checking->id, 'date' => '2026-11-18'])
            ->assertSessionHasErrors('account_id');
    }

    public function test_dashboard_balance_excludes_cards_and_shows_open_invoices(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $this->purchase($card, ['amount' => 1200, 'is_installment' => true, 'installments_count' => 3]);

        $this->actingAs($this->user)
            ->get(route('dashboard'))
            ->assertInertia(fn (Assert $page) => $page
                ->where('kpis.total_balance', fn ($v) => (float) $v === 5000.0)
                // Só a fatura atual (dez): 333,75 + 1ª parcela 400. Parcelas futuras ficam de fora.
                ->where('kpis.open_invoices', 733.75));
    }

    public function test_changing_closing_day_reassigns_unpaid_purchases(): void
    {
        $card = $this->createCard();
        $this->purchase($card, ['date' => '2026-11-10']);

        $this->actingAs($this->user)
            ->put(route('accounts.update', $card), [
                'name' => 'Nubank',
                'credit_limit' => 5000,
                'closing_day' => 5,
                'due_day' => 12,
                'payment_account_id' => $this->checking->id,
            ])
            ->assertSessionHasNoErrors();

        $invoice = Transaction::firstOrFail()->invoice;

        // 10/11 é depois do fechamento (5) → fecha 05/12, vence 12/12.
        $this->assertSame('2026-12-05', $invoice->closing_date->toDateString());
        $this->assertSame('2026-12-12', $invoice->due_date->toDateString());
        $this->assertSame(1, CreditCardInvoice::count());
    }

    public function test_moving_purchase_from_card_to_checking_hits_balance(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $transaction = Transaction::firstOrFail();

        $this->actingAs($this->user)
            ->put(route('transactions.update', $transaction), [
                'description' => 'Uber',
                'amount' => 333.75,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->checking->id,
                'date' => '2026-11-18',
            ])
            ->assertSessionHasNoErrors();

        $this->assertNull($transaction->fresh()->invoice_id);
        $this->assertEquals(4666.25, (float) $this->checking->fresh()->balance);
        $this->assertEquals(0.0, $this->summary($card)['used']);
    }

    public function test_card_page_renders_selected_invoice(): void
    {
        $card = $this->createCard();
        $this->purchase($card);

        $this->actingAs($this->user)
            ->get(route('cards.show', $card))
            ->assertOk()
            ->assertInertia(fn (Assert $page) => $page
                ->component('cards/show')
                ->has('invoices', 1)
                ->where('selectedInvoice.total', 333.75)
                ->has('transactions', 1));
    }

    public function test_card_purchases_stay_in_the_invoice_until_it_is_paid(): void
    {
        $card = $this->createCard();
        $this->purchase($card, ['date' => '2026-11-02']);
        $transaction = Transaction::firstOrFail();
        $invoice = CreditCardInvoice::firstOrFail();

        // Não nasce paga e não fica "atrasada". Pela visão "por pagamento", a compra de 02/11
        // aparece em dezembro (fatura vence 05/12).
        $this->assertNull($transaction->paid_at);
        $this->actingAs($this->user)
            ->get(route('transactions.index', ['status' => 'overdue', 'month' => '2026-12']))
            ->assertInertia(fn (Assert $page) => $page->has('transactions.data', 0));
        $this->actingAs($this->user)
            ->get(route('transactions.index', ['status' => 'pending', 'month' => '2026-12']))
            ->assertInertia(fn (Assert $page) => $page->has('transactions.data', 1));
        $this->actingAs($this->user)
            ->get(route('transactions.index', ['status' => 'pending', 'view' => 'purchase']))
            ->assertInertia(fn (Assert $page) => $page->has('transactions.data', 1));

        $this->actingAs($this->user)
            ->post(route('invoices.pay', $invoice), ['account_id' => $this->checking->id, 'date' => '2026-11-18']);
        $this->assertSame('2026-11-18', $transaction->fresh()->paid_at?->toDateString());

        $this->actingAs($this->user)->delete(route('invoices.undo', $invoice));
        $this->assertNull($transaction->fresh()->paid_at);
    }

    public function test_card_purchase_cannot_be_marked_paid_by_hand(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $transaction = Transaction::firstOrFail();

        $this->actingAs($this->user)
            ->post(route('transactions.pay', $transaction))
            ->assertSessionHasErrors('paid');

        $this->assertNull($transaction->fresh()->paid_at);
    }

    public function test_purchase_moved_into_a_paid_invoice_is_paid(): void
    {
        $card = $this->createCard();
        $this->purchase($card, ['description' => 'Primeira']);
        $invoice = CreditCardInvoice::firstOrFail();
        $this->actingAs($this->user)
            ->post(route('invoices.pay', $invoice), ['account_id' => $this->checking->id, 'date' => '2026-11-18']);

        $this->purchase($card, ['description' => 'Segunda', 'date' => '2026-11-10']);

        $this->assertSame('2026-11-18', Transaction::where('name', 'Segunda')->firstOrFail()->paid_at?->toDateString());
    }

    public function test_purchases_can_be_reconciled_on_the_invoice(): void
    {
        $card = $this->createCard();
        $this->purchase($card);
        $transaction = Transaction::firstOrFail();

        $this->actingAs($this->user)->post(route('transactions.reconcile', $transaction))->assertRedirect();
        $this->assertNotNull($transaction->fresh()->reconciled_at);

        $this->actingAs($this->user)->post(route('transactions.reconcile', $transaction));
        $this->assertNull($transaction->fresh()->reconciled_at);

        $this->actingAs(User::factory()->create())
            ->post(route('transactions.reconcile', $transaction))
            ->assertNotFound();
    }
}
