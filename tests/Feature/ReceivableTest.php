<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\ICreditCardService;
use App\Interfaces\Services\IDashboardService;
use App\Interfaces\Services\IReimbursementService;
use App\Models\Account;
use App\Models\Category;
use App\Models\Contact;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Compra para outra pessoa (ex.: o irmão usa o cartão e devolve por Pix).
 */
class ReceivableTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $checking;

    private Account $card;

    private Category $category;

    private Contact $irmao;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->user = User::factory()->create();
        app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->category = Category::where('user_id', $this->user->id)->where('name', 'Outros')->firstOrFail();

        $this->checking = Account::create(['user_id' => $this->user->id, 'name' => 'Bradesco', 'type' => 'checking', 'balance' => 1000]);
        $this->card = Account::create([
            'user_id' => $this->user->id, 'name' => 'Elo', 'type' => 'credit', 'balance' => 0,
            'credit_limit' => 5000, 'closing_day' => 25, 'due_day' => 5,
        ]);

        $this->actingAs($this->user)->post(route('contacts.store'), ['name' => 'Irmão'])->assertSessionHasNoErrors();
        $this->irmao = Contact::where('name', 'Irmão')->firstOrFail();
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function storeForBrother(array $overrides = []): Transaction
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), [
                'description' => 'Tênis do irmão',
                'amount' => 300,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->card->id,
                'date' => '2026-11-18',
                'is_installment' => false,
                'installments_count' => 2,
                'installment_start' => 1,
                'amount_mode' => 'installment',
                'is_recurring' => false,
                'frequency' => 'monthly',
                'split' => [
                    'mode' => 'equal',
                    'participants' => [['contact_id' => $this->irmao->id]],
                    'paid_by_contact_id' => null,
                    'include_me' => false,
                ],
                ...$overrides,
            ])
            ->assertSessionHasNoErrors();

        return Transaction::query()->latest('created_at')->firstOrFail();
    }

    private function brotherSplit(Transaction $transaction): TransactionSplit
    {
        return TransactionSplit::where('transaction_id', $transaction->id)->where('contact_id', $this->irmao->id)->firstOrFail();
    }

    public function test_purchase_for_someone_else_goes_to_the_invoice_but_not_to_my_expenses(): void
    {
        $transaction = $this->storeForBrother();

        $this->assertEquals(0.0, (float) $transaction->amount);
        $this->assertEquals(300.0, (float) $transaction->total_amount);
        $this->assertEquals(300.0, (float) $this->brotherSplit($transaction)->amount);

        $summary = app(ICreditCardService::class)->summary($this->card->fresh());
        $this->assertEquals(300.0, $summary['used']);

        $kpis = app(IDashboardService::class)->kpis($this->user->id);
        $this->assertEquals(0.0, (float) $kpis['expense']['value']);

        $open = app(IReimbursementService::class)->openForUser($this->user->id);
        $this->assertCount(1, $open);
        $this->assertSame('Irmão', $open[0]['contact']['name']);
        // Cartão fecha dia 25 e vence dia 5: a compra de 18/11 cai no acerto de dezembro (o da vez).
        $this->assertSame('2026-12', $open[0]['items'][0]['month']);
        $this->assertEquals(300.0, $open[0]['current_total']);
    }

    public function test_receiving_raises_the_account_balance_without_counting_as_income(): void
    {
        $split = $this->brotherSplit($this->storeForBrother());

        $this->actingAs($this->user)
            ->post(route('receivables.receive', $this->irmao), [
                'split_ids' => [$split->id],
                'account_id' => $this->checking->id,
                'date' => '2026-11-20',
            ])
            ->assertSessionHasNoErrors();

        $this->assertEquals(1300.0, (float) $this->checking->fresh()->balance);
        $this->assertSame('2026-11-20', $split->fresh()->reimbursed_at?->toDateString());

        $kpis = app(IDashboardService::class)->kpis($this->user->id);
        $this->assertEquals(0.0, (float) $kpis['income']['value']);
        $this->assertSame([], app(IReimbursementService::class)->openForUser($this->user->id));
    }

    public function test_undo_takes_the_money_back_out(): void
    {
        $split = $this->brotherSplit($this->storeForBrother());

        $this->actingAs($this->user)->post(route('receivables.receive', $this->irmao), [
            'split_ids' => [$split->id], 'account_id' => $this->checking->id, 'date' => '2026-11-20',
        ]);

        $this->actingAs($this->user)->delete(route('receivables.undo', $split))->assertSessionHasNoErrors();

        $this->assertEquals(1000.0, (float) $this->checking->fresh()->balance);
        $this->assertNull($split->fresh()->reimbursed_at);
    }

    public function test_editing_the_purchase_keeps_the_reimbursement(): void
    {
        $transaction = $this->storeForBrother();
        $split = $this->brotherSplit($transaction);

        $this->actingAs($this->user)->post(route('receivables.receive', $this->irmao), [
            'split_ids' => [$split->id], 'account_id' => $this->checking->id, 'date' => '2026-11-20',
        ]);

        $this->actingAs($this->user)
            ->put(route('transactions.update', $transaction), [
                'description' => 'Tênis (editado)',
                'amount' => 300,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->card->id,
                'date' => '2026-11-18',
                'split' => [
                    'mode' => 'equal',
                    'participants' => [['contact_id' => $this->irmao->id]],
                    'paid_by_contact_id' => null,
                    'include_me' => false,
                ],
            ])
            ->assertSessionHasNoErrors();

        $this->assertNotNull($this->brotherSplit($transaction)->reimbursed_at);
        $this->assertEquals(1300.0, (float) $this->checking->fresh()->balance);
    }

    public function test_deleting_the_purchase_reverts_the_reimbursement(): void
    {
        $transaction = $this->storeForBrother();
        $split = $this->brotherSplit($transaction);

        $this->actingAs($this->user)->post(route('receivables.receive', $this->irmao), [
            'split_ids' => [$split->id], 'account_id' => $this->checking->id, 'date' => '2026-11-20',
        ]);

        $this->actingAs($this->user)->delete(route('transactions.destroy', $transaction))->assertSessionHasNoErrors();

        $this->assertEquals(1000.0, (float) $this->checking->fresh()->balance);
    }

    public function test_someone_else_cannot_be_the_payer_of_a_purchase_for_others(): void
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), [
                'description' => 'X',
                'amount' => 100,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => null,
                'date' => '2026-11-18',
                'is_installment' => false,
                'installments_count' => 2,
                'installment_start' => 1,
                'amount_mode' => 'installment',
                'is_recurring' => false,
                'frequency' => 'monthly',
                'split' => [
                    'mode' => 'equal',
                    'participants' => [['contact_id' => $this->irmao->id]],
                    'paid_by_contact_id' => $this->irmao->id,
                    'include_me' => false,
                ],
            ])
            ->assertSessionHasErrors('split.paid_by_contact_id');
    }

    public function test_money_cannot_go_to_a_credit_card_or_to_another_users_contact(): void
    {
        $split = $this->brotherSplit($this->storeForBrother());

        $this->actingAs($this->user)
            ->post(route('receivables.receive', $this->irmao), [
                'split_ids' => [$split->id], 'account_id' => $this->card->id, 'date' => '2026-11-20',
            ])
            ->assertSessionHasErrors('account_id');

        $other = User::factory()->create();
        $this->actingAs($other)
            ->post(route('receivables.receive', $this->irmao), [
                'split_ids' => [$split->id], 'account_id' => $this->checking->id, 'date' => '2026-11-20',
            ])
            ->assertNotFound();
    }

    public function test_installments_for_someone_else_fall_in_each_invoice_month(): void
    {
        $this->storeForBrother([
            'description' => 'Celular do irmão',
            'amount' => 100,
            'is_installment' => true,
            'installments_count' => 3,
        ]);

        $open = app(IReimbursementService::class)->openForUser($this->user->id);

        $this->assertCount(3, $open[0]['items']);
        $this->assertSame(['current', 'upcoming', 'upcoming'], array_column($open[0]['items'], 'group'));
        $this->assertEquals(100.0, $open[0]['current_total']);
    }
}
