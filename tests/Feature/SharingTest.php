<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Models\Account;
use App\Models\Category;
use App\Models\Contact;
use App\Models\ContactInvitation;
use App\Models\Share;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

/**
 * Fase 4: convites entre usuários e compartilhamento de divisões.
 */
class SharingTest extends TestCase
{
    use RefreshDatabase;

    private User $me;

    private User $mozi;

    private Account $myChecking;

    private Account $moziChecking;

    private Category $myCategory;

    private Category $moziCategory;

    private Contact $moziContact;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->me = User::factory()->create(['name' => 'Rhaniel', 'email' => 'rhaniel@example.com']);
        $this->mozi = User::factory()->create(['name' => 'Mozi', 'email' => 'mozi@example.com']);

        foreach ([$this->me, $this->mozi] as $user) {
            app(IAccountService::class)->createDefaultForUser($user->id);
            app(ICategoryService::class)->createDefaultsForUser($user->id);
        }

        $this->myChecking = Account::create(['user_id' => $this->me->id, 'name' => 'Bradesco', 'type' => 'checking', 'balance' => 1000]);
        $this->moziChecking = Account::create(['user_id' => $this->mozi->id, 'name' => 'Nubank', 'type' => 'checking', 'balance' => 1000]);

        $this->myCategory = Category::where('user_id', $this->me->id)->where('name', 'Transporte')->firstOrFail();
        $this->moziCategory = Category::where('user_id', $this->mozi->id)->where('name', 'Transporte')->firstOrFail();

        $this->moziContact = Contact::create(['user_id' => $this->me->id, 'name' => 'Mozi']);
    }

    private function connect(): void
    {
        $this->actingAs($this->me)
            ->post(route('contacts.invite', $this->moziContact), ['email' => 'Mozi@Example.com'])
            ->assertSessionHasNoErrors();

        $invitation = ContactInvitation::firstOrFail();

        $this->actingAs($this->mozi)
            ->post(route('invitations.accept', $invitation))
            ->assertRedirect();
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function splitPayload(array $overrides = [], ?string $paidBy = null): array
    {
        return [
            'description' => 'Empréstimo Caixa',
            'amount' => 200,
            'type' => 'expense',
            'category_id' => $this->myCategory->id,
            'account_id' => $paidBy === null ? $this->myChecking->id : null,
            'date' => '2026-11-18',
            'is_installment' => false,
            'installments_count' => 2,
            'installment_start' => 1,
            'amount_mode' => 'total',
            'is_recurring' => false,
            'frequency' => 'monthly',
            'split' => [
                'mode' => 'equal',
                'participants' => [['contact_id' => null], ['contact_id' => $this->moziContact->id]],
                'paid_by_contact_id' => $paidBy,
            ],
            ...$overrides,
        ];
    }

    private function createSplit(array $overrides = [], ?string $paidBy = null): Transaction
    {
        $this->actingAs($this->me)
            ->post(route('transactions.store'), $this->splitPayload($overrides, $paidBy))
            ->assertSessionHasNoErrors();

        return Transaction::where('user_id', $this->me->id)->orderBy('date')->firstOrFail();
    }

    private function accept(?string $accountId = null): void
    {
        $this->actingAs($this->mozi)
            ->post(route('shares.accept', Share::firstOrFail()), [
                'category_id' => $this->moziCategory->id,
                'account_id' => $accountId,
            ])
            ->assertSessionHasNoErrors();
    }

    private function mirrors()
    {
        return Transaction::where('user_id', $this->mozi->id)->whereNotNull('mirrored_from_id')->orderBy('date')->get();
    }

    public function test_accepting_invitation_links_both_sides(): void
    {
        $this->connect();

        $this->assertSame($this->mozi->id, $this->moziContact->fresh()->linked_user_id);
        $this->assertDatabaseHas('contacts', ['user_id' => $this->mozi->id, 'name' => 'Rhaniel', 'linked_user_id' => $this->me->id]);
        $this->assertSame('accepted', ContactInvitation::firstOrFail()->status);
        $this->assertSame(1, $this->me->notifications()->count());
    }

    public function test_cannot_invite_yourself_and_invite_waits_for_future_users(): void
    {
        $this->actingAs($this->me)
            ->post(route('contacts.invite', $this->moziContact), ['email' => 'rhaniel@example.com'])
            ->assertSessionHasErrors('email');

        $mae = Contact::create(['user_id' => $this->me->id, 'name' => 'Mãe da Mozi']);
        $this->actingAs($this->me)->post(route('contacts.invite', $mae), ['email' => 'mae@example.com']);

        // Ela entra no Phamani depois: o convite aparece em Pendências.
        $newUser = User::factory()->create(['email' => 'mae@example.com']);

        $this->actingAs($newUser)
            ->get(route('inbox'))
            ->assertInertia(fn (Assert $page) => $page->component('inbox/index')->has('invitations', 1));
    }

    public function test_split_with_linked_contact_asks_for_acceptance(): void
    {
        $this->connect();
        $this->createSplit();

        $share = Share::firstOrFail();
        $this->assertSame('pending', $share->status);
        $this->assertSame($this->mozi->id, $share->recipient_user_id);
        $this->assertCount(0, $this->mirrors());

        $this->actingAs($this->mozi)
            ->get(route('inbox'))
            ->assertInertia(fn (Assert $page) => $page
                ->has('pendingShares', 1)
                ->where('pendingShares.0.my_amount', 100)
                ->where('notifications.pending', 1));
    }

    public function test_accepting_creates_her_part_without_touching_her_balance(): void
    {
        $this->connect();
        $source = $this->createSplit();
        $this->accept();

        $mirror = $this->mirrors()->first();

        $this->assertNotNull($mirror);
        $this->assertSame($source->id, $mirror->mirrored_from_id);
        $this->assertEquals(100.0, (float) $mirror->amount);
        $this->assertEquals(200.0, (float) $mirror->total_amount);
        $this->assertSame($this->moziCategory->id, $mirror->category_id);
        $this->assertNull($mirror->account_id);
        $this->assertSame(
            Contact::where('user_id', $this->mozi->id)->where('linked_user_id', $this->me->id)->value('id'),
            $mirror->paid_by_contact_id,
        );
        $this->assertEquals(1000.0, (float) $this->moziChecking->fresh()->balance);
        $this->assertEquals(800.0, (float) $this->myChecking->fresh()->balance);

        // A parte dela entra como despesa dela.
        $this->actingAs($this->mozi)
            ->get(route('dashboard'))
            ->assertInertia(fn (Assert $page) => $page->where('kpis.expense.value', fn ($v) => (float) $v === 100.0));
    }

    public function test_when_she_paid_her_chosen_account_is_debited(): void
    {
        $this->connect();
        $this->createSplit(paidBy: $this->moziContact->id);
        $this->accept($this->moziChecking->id);

        $this->assertEquals(800.0, (float) $this->moziChecking->fresh()->balance);
        $this->assertEquals(1000.0, (float) $this->myChecking->fresh()->balance);
    }

    public function test_owner_changes_propagate_and_removal_deletes_her_copy(): void
    {
        $this->connect();
        $source = $this->createSplit();
        $this->accept();

        $update = fn (?array $split) => $this->actingAs($this->me)
            ->put(route('transactions.update', $source), [
                'description' => 'Empréstimo Caixa',
                'amount' => 300,
                'type' => 'expense',
                'category_id' => $this->myCategory->id,
                'account_id' => $this->myChecking->id,
                'date' => '2026-11-18',
                'split' => $split,
            ])
            ->assertSessionHasNoErrors();

        $update($this->splitPayload()['split']);
        $this->assertEquals(150.0, (float) $this->mirrors()->first()->amount);

        $update(null);
        $this->assertCount(0, $this->mirrors());
        $this->assertSame('removed', Share::firstOrFail()->status);
    }

    public function test_deleting_the_original_deletes_her_copy(): void
    {
        $this->connect();
        $source = $this->createSplit();
        $this->accept();

        $this->actingAs($this->me)->delete(route('transactions.destroy', $source))->assertRedirect();

        $this->assertCount(0, $this->mirrors());
    }

    public function test_recurring_series_is_accepted_once(): void
    {
        $this->connect();
        $this->createSplit(['is_recurring' => true]);
        $this->accept();

        $this->travelTo('2026-12-18 01:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $this->assertSame(1, Share::count());
        $this->assertSame(['2026-11-18', '2026-12-18'], $this->mirrors()->map(fn ($t) => $t->date->toDateString())->all());
    }

    public function test_declined_series_stays_out(): void
    {
        $this->connect();
        $this->createSplit(['is_recurring' => true]);

        $this->actingAs($this->mozi)->post(route('shares.decline', Share::firstOrFail()))->assertRedirect();

        $this->travelTo('2026-12-18 01:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $this->assertSame('declined', Share::firstOrFail()->status);
        $this->assertCount(0, $this->mirrors());
    }

    public function test_leaving_removes_her_copies(): void
    {
        $this->connect();
        $this->createSplit(['amount' => 300, 'is_installment' => true, 'installments_count' => 3]);
        $this->accept();
        $this->assertCount(3, $this->mirrors());

        $this->actingAs($this->mozi)->post(route('shares.leave', Share::firstOrFail()))->assertRedirect();

        $this->assertCount(0, $this->mirrors());
        $this->assertSame('left', Share::firstOrFail()->status);
    }

    public function test_she_cannot_edit_the_copy_and_strangers_cannot_answer(): void
    {
        $this->connect();
        $this->createSplit();
        $this->accept();
        $mirror = $this->mirrors()->first();

        $this->actingAs($this->mozi)
            ->put(route('transactions.update', $mirror), [
                'description' => 'Hackeado',
                'amount' => 1,
                'type' => 'expense',
                'category_id' => $this->moziCategory->id,
                'account_id' => $this->moziChecking->id,
                'date' => '2026-11-18',
            ])
            ->assertRedirect();
        $this->assertEquals(100.0, (float) $mirror->fresh()->amount);

        $stranger = User::factory()->create();
        app(ICategoryService::class)->createDefaultsForUser($stranger->id);
        $this->actingAs($stranger)
            ->post(route('shares.decline', Share::firstOrFail()))
            ->assertNotFound();
    }

    public function test_after_unlinking_new_splits_are_not_shared(): void
    {
        $this->connect();

        $this->actingAs($this->me)->post(route('contacts.unlink', $this->moziContact))->assertRedirect();
        $this->createSplit();

        $this->assertNull($this->moziContact->fresh()->linked_user_id);
        $this->assertSame(0, Share::count());
    }

    public function test_linking_later_shares_upcoming_parcels_only(): void
    {
        // Parcelamento dividido ANTES do convite: out/2026 (passado), nov (mês atual), dez e jan (futuras).
        $this->createSplit([
            'amount' => 400,
            'date' => '2026-10-18',
            'is_installment' => true,
            'installments_count' => 4,
        ]);
        $this->assertSame(0, Share::count());

        $this->connect();

        $share = Share::firstOrFail();
        $this->assertSame('pending', $share->status);
        $this->assertSame(3, $share->links()->count()); // nov, dez, jan

        $this->accept();
        $this->assertSame(
            ['2026-11-18', '2026-12-18', '2027-01-18'],
            $this->mirrors()->map(fn ($t) => $t->date->toDateString())->all(),
        );
    }

    public function test_share_upcoming_command_is_idempotent(): void
    {
        $this->createSplit(['amount' => 300, 'is_installment' => true, 'installments_count' => 3]);

        // Vínculo feito "por fora" (como nos dados de antes desta correção).
        $this->moziContact->update(['linked_user_id' => $this->mozi->id]);
        Contact::create(['user_id' => $this->mozi->id, 'name' => 'Rhaniel', 'linked_user_id' => $this->me->id]);

        $this->artisan('phamani:share-upcoming')->assertSuccessful();
        $this->artisan('phamani:share-upcoming')->assertSuccessful();

        $this->assertSame(1, Share::count());
        $this->assertSame(3, Share::firstOrFail()->links()->count());
    }

    public function test_contacts_can_be_renamed(): void
    {
        Contact::create(['user_id' => $this->me->id, 'name' => 'Outro']);

        $this->actingAs($this->me)
            ->put(route('contacts.update', $this->moziContact), ['name' => 'Outro'])
            ->assertSessionHasErrors('name');

        $this->actingAs($this->me)
            ->put(route('contacts.update', $this->moziContact), ['name' => 'Márcia'])
            ->assertSessionHasNoErrors();

        $this->assertSame('Márcia', $this->moziContact->fresh()->name);

        $this->actingAs($this->mozi)
            ->put(route('contacts.update', $this->moziContact), ['name' => 'X'])
            ->assertNotFound();
    }
}
