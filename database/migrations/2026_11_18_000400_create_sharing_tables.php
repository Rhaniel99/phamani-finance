<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Fase 4 — convites entre usuários e compartilhamento de divisões.
 *
 * - contact_invitations: convite para vincular um contato a um usuário (pelo e-mail do Google).
 * - shares: pedido de compartilhamento de UMA série (transação avulsa, parcelamento ou recorrência)
 *   para um usuário vinculado. Aceito uma vez, vale para a série inteira.
 * - share_links: cada transação da série × a cópia criada no sistema de quem aceitou.
 * - transactions.mirrored_from_id: a cópia aponta para a transação original (somente leitura).
 * - notifications: tabela padrão das Laravel Notifications (canal "database"; depois dá para
 *   ligar o "broadcast" com Reverb sem mudar nada aqui).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('contact_invitations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('contact_id')->constrained()->cascadeOnDelete();
            $table->string('email');
            $table->enum('status', ['pending', 'accepted', 'declined', 'cancelled'])->default('pending');
            $table->foreignUuid('recipient_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('responded_at')->nullable();
            $table->timestamps();

            $table->index(['email', 'status']);
        });

        Schema::create('shares', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('owner_user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('recipient_user_id')->constrained('users')->cascadeOnDelete();
            // Contato do dono que representa quem recebe.
            $table->foreignUuid('owner_contact_id')->constrained('contacts')->cascadeOnDelete();
            $table->enum('source_type', ['transaction', 'installment', 'recurring']);
            $table->uuid('source_id');
            $table->enum('status', ['pending', 'accepted', 'declined', 'left', 'removed'])->default('pending');
            // Escolhas de quem recebe, ao aceitar.
            $table->foreignUuid('category_id')->nullable()->constrained('categories')->nullOnDelete();
            $table->foreignUuid('account_id')->nullable()->constrained('accounts')->nullOnDelete();
            $table->timestamp('responded_at')->nullable();
            $table->timestamps();

            $table->unique(['recipient_user_id', 'source_type', 'source_id']);
            $table->index(['recipient_user_id', 'status']);
        });

        Schema::table('transactions', function (Blueprint $table) {
            $table->foreignUuid('mirrored_from_id')->nullable()->constrained('transactions')->nullOnDelete();
        });

        Schema::create('share_links', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('share_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('source_transaction_id')->constrained('transactions')->cascadeOnDelete();
            $table->foreignUuid('mirror_transaction_id')->nullable()->constrained('transactions')->nullOnDelete();
            $table->timestamps();

            $table->unique(['share_id', 'source_transaction_id']);
        });

        if (! Schema::hasTable('notifications')) {
            Schema::create('notifications', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->string('type');
                $table->uuidMorphs('notifiable');
                $table->text('data');
                $table->timestamp('read_at')->nullable();
                $table->timestamps();
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('share_links');

        Schema::table('transactions', function (Blueprint $table) {
            $table->dropConstrainedForeignId('mirrored_from_id');
        });

        Schema::dropIfExists('shares');
        Schema::dropIfExists('contact_invitations');
        Schema::dropIfExists('notifications');
    }
};
