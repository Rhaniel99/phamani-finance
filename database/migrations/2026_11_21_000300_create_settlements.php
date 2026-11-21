<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Acerto do mês ("quem me deve" / "quanto eu devo").
 *
 * - contacts.track_debts: cobrar essa pessoa no acerto (padrão: sim).
 * - transaction_splits.tracked: esta parte entra no acerto de quem pagou.
 * - settlements: pagamento informado por quem deve (usuário do Phamani) e confirmado por quem recebe.
 *   pending = "paguei" (saiu da conta de quem deve) → confirmed (entrou na conta de quem recebe) ou rejected.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('contacts', function (Blueprint $table) {
            $table->boolean('track_debts')->default(true);
        });

        Schema::create('settlements', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('creditor_user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('debtor_user_id')->constrained('users')->cascadeOnDelete();
            // Contato de quem recebe que representa quem pagou.
            $table->foreignUuid('contact_id')->constrained('contacts')->cascadeOnDelete();
            $table->decimal('amount', 12, 2);
            $table->date('paid_on');
            $table->foreignUuid('from_account_id')->nullable()->constrained('accounts')->nullOnDelete();
            $table->foreignUuid('to_account_id')->nullable()->constrained('accounts')->nullOnDelete();
            $table->string('status', 20)->default('pending');
            $table->timestamp('confirmed_at')->nullable();
            $table->timestamps();

            $table->index(['creditor_user_id', 'status']);
            $table->index(['debtor_user_id', 'status']);
        });

        Schema::table('transaction_splits', function (Blueprint $table) {
            $table->boolean('tracked')->default(false);
            $table->foreignUuid('settlement_id')->nullable()->constrained('settlements')->nullOnDelete();
        });

        // Divisões já lançadas, pagas por quem criou: entram no acerto.
        DB::table('transaction_splits')
            ->whereNotNull('contact_id')
            ->where('amount', '>', 0)
            ->whereIn('transaction_id', DB::table('transactions')
                ->select('id')
                ->where('type', 'expense')
                ->whereNull('paid_by_contact_id')
                ->whereNull('mirrored_from_id'))
            ->update(['tracked' => true]);
    }

    public function down(): void
    {
        Schema::table('transaction_splits', function (Blueprint $table) {
            $table->dropConstrainedForeignId('settlement_id');
            $table->dropColumn('tracked');
        });

        Schema::dropIfExists('settlements');

        Schema::table('contacts', function (Blueprint $table) {
            $table->dropColumn('track_debts');
        });
    }
};
