<?php

namespace Tests\Feature;

use App\DTOs\Transaction\StoreTransactionData;
use App\Enums\RecurringFrequency;
use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\ICreditCardService;
use App\Interfaces\Services\ITransactionService;
use App\Models\Account;
use App\Models\Category;
use App\Models\CreditCardInvoice;
use App\Models\Installment;
use App\Models\RecurringTransaction;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Excluir conta/cartão: confirmação pelo nome, tudo que é da conta some, o resto fica intacto.
 */
class AccountDeletionTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $wallet;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-27 10:00:00');

        $this->user = User::factory()->create();
        $this->wallet = app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);

        $this->category = Category::query()
            ->where('user_id', $this->user->id)
            ->whereIn('type', ['expense', 'both'])
            ->firstOrFail();
    }

    private function account(string $name, string $type = 'checking', float $balance = 0): Account
    {
        return Account::create([
            'user_id' => $this->user->id,
            'name' => $name,
            'type' => $type,
            'balance' => $balance,
            'credit_limit' => $type === 'credit' ? 3000 : null,
            'closing_day' => $type === 'credit' ? 25 : null,
            'due_day' => $type === 'credit' ? 5 : null,
        ]);
    }

    private function expense(Account $account, float $amount, string $date, array $extra = []): void
    {
        app(ITransactionService::class)->create($this->user->id, StoreTransactionData::from([
            'description' => 'Compra',
            'amount' => $amount,
            'type' => 'expense',
            'category_id' => $this->category->id,
            'account_id' => $account->id,
            'date' => $date,
            ...$extra,
        ]));
    }

    public function test_impact_lists_what_will_be_deleted(): void
    {
        $bank = $this->account('Bradesco', 'checking', 500);
        $this->expense($bank, 50, '2026-11-20');
        $this->expense($bank, 300, '2026-11-20', ['is_installment' => true, 'installments_count' => 3]);
        $this->expense($bank, 40, '2026-11-01', ['is_recurring' => true, 'frequency' => RecurringFrequency::MONTHLY->value]);

        $this->actingAs($this->user)
            ->getJson(route('accounts.impact', $bank))
            ->assertOk()
            ->assertJson([
                'installments' => 1,
                'recurring' => 1,
                'is_last' => false,
            ])
            ->assertJsonPath('transactions', Transaction::query()->where('account_id', $bank->id)->count());
    }

    public function test_deleting_requires_typing_the_account_name(): void
    {
        $bank = $this->account('Bradesco');

        $this->actingAs($this->user)
            ->delete(route('accounts.destroy', $bank), ['confirm' => 'outra coisa'])
            ->assertSessionHasErrors('confirm');

        $this->assertModelExists($bank);
    }

    public function test_deleting_removes_the_account_and_everything_in_it_only(): void
    {
        $bank = $this->account('Bradesco', 'checking', 1000);
        $this->expense($bank, 50, '2026-11-20');
        $this->expense($bank, 300, '2026-11-20', ['is_installment' => true, 'installments_count' => 3]);
        $this->expense($bank, 40, '2026-11-01', ['is_recurring' => true, 'frequency' => RecurringFrequency::MONTHLY->value]);
        $this->expense($this->wallet, 25, '2026-11-20');

        $this->actingAs($this->user)
            ->delete(route('accounts.destroy', $bank), ['confirm' => ' bradesco '])
            ->assertSessionHasNoErrors()
            ->assertRedirect();

        $this->assertModelMissing($bank);
        $this->assertSame(0, Transaction::query()->where('account_id', $bank->id)->count());
        $this->assertSame(0, Installment::query()->count());
        $this->assertSame(0, RecurringTransaction::query()->count());

        // A outra conta não muda.
        $this->assertSame(1, Transaction::query()->where('account_id', $this->wallet->id)->count());
        $this->assertSame('-25.00', $this->wallet->refresh()->balance);
    }

    public function test_deleting_a_card_keeps_the_money_already_paid_from_the_bank(): void
    {
        $bank = $this->account('Bradesco', 'checking', 1000);
        $card = $this->account('Elo', 'credit');
        $this->expense($card, 200, '2026-10-10');

        $invoice = CreditCardInvoice::query()->where('account_id', $card->id)->firstOrFail();
        app(ICreditCardService::class)->pay($invoice, $bank->id, '2026-11-05');
        $this->assertSame('800.00', $bank->refresh()->balance);

        $this->actingAs($this->user)
            ->from(route('cards.show', $card))
            ->delete(route('accounts.destroy', $card), ['confirm' => 'Elo'])
            ->assertRedirect(route('dashboard'));

        $this->assertModelMissing($card);
        $this->assertSame(0, CreditCardInvoice::query()->count());
        $this->assertSame('800.00', $bank->refresh()->balance);
    }

    public function test_cannot_delete_the_last_regular_account(): void
    {
        $this->account('Elo', 'credit');

        $this->actingAs($this->user)
            ->delete(route('accounts.destroy', $this->wallet), ['confirm' => 'Carteira'])
            ->assertSessionHasErrors('account');

        $this->assertModelExists($this->wallet);
        $this->assertTrue(app(IAccountService::class)->deletionImpact($this->wallet)['is_last']);
    }

    public function test_other_users_cannot_delete_or_see_the_impact(): void
    {
        $bank = $this->account('Bradesco');
        $other = User::factory()->create();

        $this->actingAs($other)->getJson(route('accounts.impact', $bank))->assertNotFound();
        $this->actingAs($other)->delete(route('accounts.destroy', $bank), ['confirm' => 'Bradesco'])->assertNotFound();
        $this->assertModelExists($bank);
    }
}
