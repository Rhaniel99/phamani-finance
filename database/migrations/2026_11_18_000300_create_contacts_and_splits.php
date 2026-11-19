<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Fase 3 — Contatos e divisão de contas.
 *
 * - contacts: pessoas com quem você divide (só um nome). linked_user_id fica pronto para a fase 4,
 *   quando um contato poderá ser vinculado a um usuário do sistema.
 * - transactions.amount continua sendo o que entra no SEU dashboard: numa divisão, é a sua parte.
 * - transactions.total_amount: valor cheio da compra (null quando não é dividida).
 * - transactions.paid_by_contact_id: quem pagou (null = você). Se outra pessoa pagou, nenhuma conta
 *   sua é afetada; por isso account_id passa a aceitar null.
 * - transaction_splits: a parte de cada participante (contact_id null = você).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('contacts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->string('name', 100);
            $table->foreignUuid('linked_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['user_id', 'name']);
        });

        Schema::table('transactions', function (Blueprint $table) {
            $table->uuid('account_id')->nullable()->change();
            $table->decimal('total_amount', 12, 2)->nullable();
            $table->foreignUuid('paid_by_contact_id')->nullable()->constrained('contacts')->restrictOnDelete();
        });

        Schema::table('recurring_transactions', function (Blueprint $table) {
            $table->uuid('account_id')->nullable()->change();
        });

        Schema::create('transaction_splits', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('transaction_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('contact_id')->nullable()->constrained()->restrictOnDelete();
            $table->decimal('amount', 12, 2);
            $table->timestamps();

            $table->index('transaction_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transaction_splits');

        Schema::table('transactions', function (Blueprint $table) {
            $table->dropConstrainedForeignId('paid_by_contact_id');
            $table->dropColumn('total_amount');
        });

        Schema::dropIfExists('contacts');
    }
};
