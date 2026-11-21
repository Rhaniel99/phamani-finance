<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\IReimbursementService;
use App\Models\Account;
use App\Models\Category;
use App\Models\Contact;
use App\Models\ContactInvitation;
use App\Models\Settlement;
use App\Models\Share;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use App\Models\User;
use App\Support\Acerto;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Acerto do mês: Márcia paga e divide; Rhaniel informa o pagamento; Márcia confirma.
 */
class SettlementTest extends TestCase
{
    use RefreshDatabase;

    private User $marcia;

    private User $rhaniel;

    private Account $marciaChecking;

    private Account $rhanielChecking;

    private Category $marciaCategory;

    private Contact $rhanielContact;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->marcia = User::factory()->create(['name' => 'Márcia', 'email' => 'marcia@example.com']);
        $this->rhaniel = User::factory()->create(['name' => 'Rhaniel', 'email' => 'rhaniel@example.com']);

        foreach ([$this->marcia, $this->rhaniel] as $user) {
            app(IAccountService::class)->createDefaultForUser($user->id);
            app(ICategoryService::class)->createDefaultsForUser($user->id);
        }

        $this->marciaChecking = Account::create(['user_id' => $this->marcia->id, 'name' => 'Nubank', 'type' => 'checking', 'balance' => 1000]);
        $this->rhanielChecking = Account::create(['user_id' => $this->rhaniel->id, 'name' => 'Bradesco', 'type' => 'checking', 'balance' => 1000]);
        $this->marciaCategory = Category::where('user_id', $this->marcia->id)->where('name', 'Transporte')->firstOrFail();

        $this->rhanielContact = Contact::create(['user_id' => $this->marcia->id, 'name' => 'Rhaniel']);

        // Convite aceito: Rhaniel vira usuário vinculado ao contato da Márcia.
        $this->actingAs($this->marcia)
            ->post(route('contacts.invite', $this->rhanielContact), ['email' => 'rhaniel@example.com'])
            ->assertSessionHasNoErrors();
        $this->actingAs($this->rhaniel)->post(route('invitations.accept', ContactInvitation::firstOrFail()));
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function marciaSplits(array $overrides = [], array $split = []): Transaction
    {
        $this->actingAs($this->marcia)
            ->post(route('transactions.store'), [
                'description' => 'Uber',
                'amount' => 300,
                'type' => 'expense',
                'category_id' => $this->marciaCategory->id,
                'account_id' => $this->marciaChecking->id,
                'date' => '2026-11-18',
                'is_installment' => false,
                'installments_count' => 2,
                'installment_start' => 1,
                'amount_mode' => 'total',
                'is_recurring' => false,
                'frequency' => 'monthly',
                'split' => [
                    'mode' => 'equal',
                    'participants' => [['contact_id' => null], ['contact_id' => $this->rhanielContact->id]],
                    'paid_by_contact_id' => null,
                    ...$split,
                ],
                ...$overrides,
            ])
            ->assertSessionHasNoErrors();

        $transaction = Transaction::where('user_id', $this->marcia->id)->latest('created_at')->firstOrFail();

        // Rhaniel aceita a divisão.
        $share = Share::query()->where('recipient_user_id', $this->rhaniel->id)->where('status', 'pending')->first();
        if ($share !== null) {
            $this->actingAs($this->rhaniel)
                ->post(route('shares.accept', $share), [
                    'category_id' => Category::where('user_id', $this->rhaniel->id)->where('name', 'Transporte')->value('id'),
                ])
                ->assertSessionHasNoErrors();
        }

        return $transaction;
    }

    private function rhanielPart(Transaction $transaction): TransactionSplit
    {
        return TransactionSplit::where('transaction_id', $transaction->id)->where('contact_id', $this->rhanielContact->id)->firstOrFail();
    }

    private function balance(Account $account): float
    {
        return (float) $account->fresh()->balance;
    }

    public function test_partial_split_enters_both_sides_of_the_acerto(): void
    {
        $part = $this->rhanielPart($this->marciaSplits());

        $this->assertTrue($part->tracked);

        $receivables = app(IReimbursementService::class)->openForUser($this->marcia->id);
        $this->assertSame('Rhaniel', $receivables[0]['contact']['name']);
        $this->assertCount(1, $receivables[0]['items']);
        $this->assertEquals(150.0, $receivables[0]['items'][0]['amount']);

        $payables = app(IReimbursementService::class)->payablesForUser($this->rhaniel->id);
        $this->assertSame('Márcia', $payables[0]['creditor']['name']);
        $this->assertEquals(150.0, $payables[0]['items'][0]['amount']);
    }

    public function test_contact_with_tracking_off_or_division_switched_off_is_not_charged(): void
    {
        $this->assertFalse($this->rhanielPart($this->marciaSplits([], ['track' => false]))->tracked);

        $this->rhanielContact->update(['track_debts' => false]);
        $this->assertFalse($this->rhanielPart($this->marciaSplits(['description' => 'Outro']))->tracked);
    }

    public function test_pay_then_confirm_moves_money_between_both_accounts(): void
    {
        $part = $this->rhanielPart($this->marciaSplits());
        $marciaBefore = $this->balance($this->marciaChecking);

        $this->actingAs($this->rhaniel)
            ->post(route('payables.pay', $this->marcia), [
                'split_ids' => [$part->id], 'account_id' => $this->rhanielChecking->id, 'date' => '2026-11-20',
            ])
            ->assertSessionHasNoErrors();

        $settlement = Settlement::firstOrFail();
        $this->assertSame('pending', $settlement->status);
        $this->assertEquals(850.0, $this->balance($this->rhanielChecking));
        $this->assertSame([], app(IReimbursementService::class)->payablesForUser($this->rhaniel->id)[0]['items']);

        $this->actingAs($this->marcia)
            ->post(route('settlements.confirm', $settlement), ['to_account_id' => $this->marciaChecking->id])
            ->assertSessionHasNoErrors();

        $this->assertSame('confirmed', $settlement->fresh()->status);
        $this->assertEquals($marciaBefore + 150, $this->balance($this->marciaChecking));
        $this->assertNotNull($part->fresh()->reimbursed_at);
        $this->assertSame([], app(IReimbursementService::class)->payablesForUser($this->rhaniel->id));
    }

    public function test_reject_returns_the_money_and_the_items(): void
    {
        $part = $this->rhanielPart($this->marciaSplits());

        $this->actingAs($this->rhaniel)->post(route('payables.pay', $this->marcia), [
            'split_ids' => [$part->id], 'account_id' => $this->rhanielChecking->id, 'date' => '2026-11-20',
        ]);

        $this->actingAs($this->marcia)
            ->post(route('settlements.reject', Settlement::firstOrFail()))
            ->assertSessionHasNoErrors();

        $this->assertEquals(1000.0, $this->balance($this->rhanielChecking));
        $this->assertNull($part->fresh()->settlement_id);
        $this->assertCount(1, app(IReimbursementService::class)->payablesForUser($this->rhaniel->id)[0]['items']);
    }

    public function test_only_the_creditor_confirms(): void
    {
        $part = $this->rhanielPart($this->marciaSplits());

        $this->actingAs($this->rhaniel)->post(route('payables.pay', $this->marcia), [
            'split_ids' => [$part->id], 'account_id' => $this->rhanielChecking->id, 'date' => '2026-11-20',
        ]);

        $this->actingAs($this->rhaniel)
            ->post(route('settlements.confirm', Settlement::firstOrFail()), ['to_account_id' => $this->rhanielChecking->id])
            ->assertNotFound();
    }

    public function test_deleting_a_paid_purchase_reverts_both_balances(): void
    {
        $transaction = $this->marciaSplits();
        $part = $this->rhanielPart($transaction);
        $marciaBefore = $this->balance($this->marciaChecking);

        $this->actingAs($this->rhaniel)->post(route('payables.pay', $this->marcia), [
            'split_ids' => [$part->id], 'account_id' => $this->rhanielChecking->id, 'date' => '2026-11-20',
        ]);
        $this->actingAs($this->marcia)->post(route('settlements.confirm', Settlement::firstOrFail()), ['to_account_id' => $this->marciaChecking->id]);

        $this->actingAs($this->marcia)->delete(route('transactions.destroy', $transaction))->assertSessionHasNoErrors();

        $this->assertEquals(1000.0, $this->balance($this->rhanielChecking));
        // A compra (R$ 300) volta para a conta da Márcia; o acerto que tinha entrado (R$ 150) sai.
        $this->assertEquals($marciaBefore + 300, $this->balance($this->marciaChecking));
        $this->assertSame(0, Settlement::count());
    }

    public function test_acerto_calendar(): void
    {
        // Dezembro/2026: 1 (ter), 2, 3, 4, 7 → 5º dia útil = 07/12.
        $this->assertSame('2026-12-07', Acerto::deadline('2026-12')->toDateString());
        // Novembro/2026: 2 é feriado → 3, 4, 5, 6, 9.
        $this->assertSame('2026-11-09', Acerto::deadline('2026-11')->toDateString());

        // 18/11 já passou do prazo de novembro: o acerto da vez é dezembro.
        $this->assertSame('2026-12', Acerto::current(CarbonImmutable::parse('2026-11-18')));
        $this->assertSame('2026-11', Acerto::current(CarbonImmutable::parse('2026-11-05')));

        // Compra no cartão entra no mês da fatura.
        $this->assertSame('2027-01', Acerto::monthOf(CarbonImmutable::parse('2026-12-28'), CarbonImmutable::parse('2027-01-07')));
        $this->assertSame('overdue', Acerto::group('2026-11', '2026-12'));
    }
}
